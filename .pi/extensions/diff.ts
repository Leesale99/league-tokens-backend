/**
 * /diff — interactive git diff browser with per-hunk staging.
 *
 * Inspect working-tree changes and stage/unstage individual hunks, like a
 * visual `git add -p` / `git reset -p`.
 *
 *   /diff                    browse unstaged changes + untracked files
 *   /diff --staged           browse staged changes (unstage hunks)
 *   /diff --cached           alias for --staged
 *   /diff --all              browse everything (staged + unstaged + untracked)
 *   /diff -- <path>...       limit to paths
 *
 * Keys:
 *   ↑/↓ or j/k          navigate hunks / files / untracked files
 *   a / space / enter   stage the selected hunk (or untracked file)
 *   A                   stage the whole selected file
 *   r                   unstage the selected hunk
 *   R                   unstage the whole selected file
 *   t                   cycle view: unstaged → all → staged → unstaged
 *   ←/→ or [/]          scroll the diff preview
 *   g / G               jump to top / bottom of the list
 *   pgup/pgdn, ctrl+u/ctrl+d   page the list
 *   ctrl+r              refresh git state
 *   q / esc             close
 */

import type { ExecResult, ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { Key, matchesKey, truncateToWidth } from "@earendil-works/pi-tui";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// Diff parsing
// ---------------------------------------------------------------------------

type SectionId = "staged" | "unstaged" | "untracked";
type ViewMode = "unstaged" | "staged" | "all";
type FileStatus = "modified" | "new" | "deleted" | "renamed" | "mode" | "binary";

interface DiffLine {
	kind: "add" | "del" | "ctx";
	text: string;
}

interface Hunk {
	header: string;
	lines: DiffLine[];
}

interface DiffFile {
	path: string;
	oldPath: string | null;
	status: FileStatus;
	binary: boolean;
	modeChange: { oldMode: string; newMode: string } | null;
	hunks: Hunk[];
	/** Raw header lines (diff --git, index, mode, ---/+++ etc.) so a single hunk can be re-applied. */
	header: string[];
}

interface DiffState {
	staged: DiffFile[];
	unstaged: DiffFile[];
	untracked: string[];
}

type Item =
	| { kind: "section"; section: SectionId; title: string; subtitle: string }
	| { kind: "file"; section: SectionId; file: DiffFile }
	| { kind: "hunk"; section: SectionId; file: DiffFile; hunk: Hunk; hunkIndex: number }
	| { kind: "untracked"; path: string };

function stripAPrefix(p: string): string | null {
	return p === "/dev/null" ? null : p.startsWith("a/") ? p.slice(2) : p;
}

function stripBPrefix(p: string): string | null {
	return p === "/dev/null" ? null : p.startsWith("b/") ? p.slice(2) : p;
}

function parseDiff(text: string): DiffFile[] {
	const files: DiffFile[] = [];
	const sections = text.split(/(?=^diff --git )/m);
	for (const sec of sections) {
		if (!sec.startsWith("diff --git ")) continue;
		const lines = sec.replace(/\n$/, "").split("\n");
		const header: string[] = [];
		let binary = false;
		let oldMode = "";
		let newMode = "";
		let aPath: string | null = null;
		let bPath: string | null = null;
		let renameFrom: string | null = null;
		let renameTo: string | null = null;
		const hunks: Hunk[] = [];
		let inHunk = false;
		let cur: Hunk | null = null;

		for (const line of lines) {
			if (inHunk) {
				if (!cur) continue;
				if (line.startsWith("+")) cur.lines.push({ kind: "add", text: line });
				else if (line.startsWith("-")) cur.lines.push({ kind: "del", text: line });
				else cur.lines.push({ kind: "ctx", text: line });
				continue;
			}
			if (line.startsWith("@@")) {
				inHunk = true;
				cur = { header: line, lines: [] };
				hunks.push(cur);
				continue;
			}
			header.push(line);
			if (line.startsWith("Binary files ")) binary = true;
			else if (line.startsWith("old mode ")) oldMode = line.slice("old mode ".length).trim();
			else if (line.startsWith("new mode ")) newMode = line.slice("new mode ".length).trim();
			else if (line.startsWith("rename from ")) renameFrom = line.slice("rename from ".length);
			else if (line.startsWith("rename to ")) renameTo = line.slice("rename to ".length);
			else if (line.startsWith("--- ")) aPath = stripAPrefix(line.slice(4));
			else if (line.startsWith("+++ ")) bPath = stripBPrefix(line.slice(4));
		}

		// Fallback paths from the `diff --git a/X b/Y` line (rename headers often skip ---/+++).
		let fbA: string | null = null;
		let fbB: string | null = null;
		const rest = (lines[0] ?? "").slice("diff --git ".length);
		const bIdx = rest.lastIndexOf(" b/");
		if (bIdx !== -1) {
			const left = rest.slice(0, bIdx);
			const right = rest.slice(bIdx + 3);
			if (left.startsWith("a/")) fbA = left.slice(2);
			fbB = right === "/dev/null" ? null : right;
		}

		const path = bPath ?? renameTo ?? fbB ?? aPath ?? renameFrom ?? fbA ?? "(unknown)";
		const oldPath = aPath ?? renameFrom ?? fbA ?? path;

		const modeChange: DiffFile["modeChange"] = oldMode || newMode ? { oldMode, newMode } : null;
		let status: FileStatus = "modified";
		if (binary) status = "binary";
		else if (aPath === null && bPath !== null) status = "new";
		else if (bPath === null && aPath !== null) status = "deleted";
		else if (renameFrom !== null && renameTo !== null) status = "renamed";
		else if (modeChange && hunks.length === 0) status = "mode";

		files.push({ path, oldPath, status, binary, modeChange, hunks, header });
	}
	return files;
}

/** Rebuild a minimal, self-contained patch for one hunk so `git apply` can stage it. */
function hunkPatch(file: DiffFile, hunk: Hunk): string {
	const body = hunk.lines.map((l) => l.text).join("\n");
	return `${file.header.join("\n")}\n${hunk.header}\n${body}\n`;
}

function plural(n: number, word: string): string {
	return `${n} ${word}${n === 1 ? "" : "s"}`;
}

// ---------------------------------------------------------------------------
// Interactive viewer
// ---------------------------------------------------------------------------

type NotifyKind = "info" | "warning" | "error";

interface ViewerConfig {
	tui: { terminal: { rows: number }; requestRender(): void };
	theme: Theme;
	done: (value: boolean) => void;
	git: (args: string[]) => Promise<ExecResult>;
	fetchState: () => Promise<DiffState>;
	view: ViewMode;
	initial: DiffState;
	notify: (message: string, kind?: NotifyKind) => void;
}

const MAX_PREVIEW_LINES = 600;

class DiffViewer {
	private tui: ViewerConfig["tui"];
	private theme: Theme;
	private done: ViewerConfig["done"];
	private git: ViewerConfig["git"];
	private fetchState: ViewerConfig["fetchState"];
	private notify: ViewerConfig["notify"];

	private view: ViewMode;
	private state: DiffState;
	private items: Item[] = [];
	private selected = 0;
	private listScroll = 0;
	private previewOffset = 0;
	private busy = false;
	private error: string | null = null;

	private cachedWidth = -1;
	private cachedVersion = -1;
	private cachedLines: string[] = [];
	private version = 0;

	constructor(cfg: ViewerConfig) {
		this.tui = cfg.tui;
		this.theme = cfg.theme;
		this.done = cfg.done;
		this.git = cfg.git;
		this.fetchState = cfg.fetchState;
		this.notify = cfg.notify;
		this.view = cfg.view;
		this.state = cfg.initial;
		this.rebuildItems();
		this.ensureSelection();
	}

	// --- state -------------------------------------------------------------

	private bump(): void {
		this.version++;
	}

	private requestRender(): void {
		this.tui.requestRender();
	}

	invalidate(): void {
		this.cachedWidth = -1;
	}

	private rebuildItems(): void {
		const items: Item[] = [];
		const addFiles = (section: SectionId, title: string, files: DiffFile[]) => {
			if (files.length === 0) return;
			const hunks = files.reduce((n, f) => n + f.hunks.length, 0);
			items.push({
				kind: "section",
				section,
				title,
				subtitle: `${plural(files.length, "file")} · ${plural(hunks, "hunk")}`,
			});
			for (const f of files) {
				items.push({ kind: "file", section, file: f });
				for (let i = 0; i < f.hunks.length; i++) {
					items.push({ kind: "hunk", section, file: f, hunk: f.hunks[i], hunkIndex: i });
				}
			}
		};
		if (this.view === "staged" || this.view === "all") addFiles("staged", "Staged", this.state.staged);
		if (this.view === "unstaged" || this.view === "all") addFiles("unstaged", "Unstaged", this.state.unstaged);
		if (this.view === "unstaged" || this.view === "all") {
			if (this.state.untracked.length > 0) {
				items.push({
					kind: "section",
					section: "untracked",
					title: "Untracked",
					subtitle: plural(this.state.untracked.length, "file"),
				});
				for (const p of this.state.untracked) items.push({ kind: "untracked", path: p });
			}
		}
		this.items = items;
	}

	private ensureSelection(): void {
		if (this.items.length === 0) {
			this.selected = 0;
			return;
		}
		let i = Math.min(this.selected, this.items.length - 1);
		if (this.items[i].kind === "section") {
			const next = this.items.findIndex((it, idx) => idx >= i && it.kind !== "section");
			i = next !== -1 ? next : this.items.length - 1;
		}
		this.selected = i;
	}

	private itemKey(item: Item): string {
		switch (item.kind) {
			case "section":
				return `sec:${item.section}`;
			case "file":
				return `file:${item.section}:${item.file.path}`;
			case "hunk":
				return `hunk:${item.section}:${item.file.path}:${item.hunk.header}`;
			case "untracked":
				return `untracked:${item.path}`;
		}
	}

	private async refresh(): Promise<void> {
		const prev = this.items[this.selected];
		const prevKey = prev ? this.itemKey(prev) : null;
		const prevFile = prev && (prev.kind === "file" || prev.kind === "hunk") ? prev.file.path : null;
		const prevIndex = this.selected;
		const next = await this.fetchState();
		this.state = next;
		this.rebuildItems();
		let sel = prevKey ? this.items.findIndex((it) => this.itemKey(it) === prevKey) : -1;
		if (sel === -1 && prevFile) {
			sel = this.items.findIndex((it) => (it.kind === "file" || it.kind === "hunk") && it.file.path === prevFile);
		}
		this.selected = sel !== -1 ? sel : Math.min(prevIndex, Math.max(0, this.items.length - 1));
		this.ensureSelection();
		this.previewOffset = 0;
		this.bump();
	}

	private cycleView(): void {
		const prevKey = this.items[this.selected] ? this.itemKey(this.items[this.selected]) : null;
		this.view = this.view === "unstaged" ? "all" : this.view === "all" ? "staged" : "unstaged";
		this.rebuildItems();
		const sel = prevKey ? this.items.findIndex((it) => this.itemKey(it) === prevKey) : -1;
		this.selected = sel !== -1 ? sel : 0;
		this.ensureSelection();
		this.previewOffset = 0;
		this.bump();
	}

	private countSummary(): string {
		const s = this.state;
		const hunks = (fs: DiffFile[]) => fs.reduce((n, f) => n + f.hunks.length, 0);
		const parts: string[] = [];
		if (s.unstaged.length) parts.push(`${plural(s.unstaged.length, "file")} · ${plural(hunks(s.unstaged), "hunk")} unstaged`);
		if (s.staged.length) parts.push(`${plural(s.staged.length, "file")} · ${plural(hunks(s.staged), "hunk")} staged`);
		if (s.untracked.length) parts.push(plural(s.untracked.length, "untracked file"));
		return parts.join("  |  ") || "working tree clean";
	}

	// --- git operations ----------------------------------------------------

	private async withBusy<T>(fn: () => Promise<T>): Promise<T | undefined> {
		this.busy = true;
		this.error = null;
		this.bump();
		this.requestRender();
		try {
			return await fn();
		} catch (err) {
			this.error = (err instanceof Error ? err.message : String(err)).slice(0, 200);
			this.bump();
			this.requestRender();
			this.notify(this.error, "error");
			return undefined;
		} finally {
			this.busy = false;
			this.bump();
			this.requestRender();
		}
	}

	private async runOp(op: () => Promise<ExecResult>, okMessage: string): Promise<void> {
		const res = await this.withBusy(op);
		if (res === undefined) return;
		if (res.code !== 0) {
			this.error = (res.stderr.trim().split("\n")[0] || "git command failed").slice(0, 200);
			this.bump();
			this.requestRender();
			this.notify(this.error, "error");
			return;
		}
		if (okMessage) this.notify(okMessage, "info");
		await this.refresh();
	}

	private async forceRefresh(): Promise<void> {
		await this.withBusy(() => this.refresh());
	}

	private async applyHunk(item: Extract<Item, { kind: "hunk" }>, reverse: boolean): Promise<ExecResult> {
		const patch = hunkPatch(item.file, item.hunk);
		const dir = await mkdtemp(join(tmpdir(), "pi-diff-"));
		const file = join(dir, "hunk.patch");
		try {
			await writeFile(file, patch, "utf8");
			return await this.git([
				"apply",
				"--cached",
				...(reverse ? ["--reverse"] : []),
				"--whitespace=nowarn",
				file,
			]);
		} finally {
			await rm(dir, { recursive: true, force: true }).catch(() => {});
		}
	}

	private stage(item: Item | undefined, wholeFile: boolean): void {
		if (!item || this.busy) return;
		if (item.kind === "untracked") {
			void this.runOp(() => this.git(["add", "--", item.path]), `Staged ${item.path}`);
			return;
		}
		if (item.kind === "hunk" && item.section === "unstaged") {
			if (wholeFile) {
				void this.runOp(() => this.git(["add", "--", item.file.path]), `Staged ${item.file.path}`);
			} else {
				void this.runOp(
					() => this.applyHunk(item, false),
					`Staged hunk ${item.hunkIndex + 1} in ${item.file.path}`,
				);
			}
			return;
		}
		if (item.kind === "file" && item.section === "unstaged") {
			void this.runOp(() => this.git(["add", "--", item.file.path]), `Staged ${item.file.path}`);
			return;
		}
		this.notify(item.section === "staged" ? "Already staged — press r to unstage" : "Nothing to stage here", "info");
	}

	private unstage(item: Item | undefined, wholeFile: boolean): void {
		if (!item || this.busy) return;
		if (item.kind === "hunk" && item.section === "staged") {
			if (wholeFile) {
				void this.runOp(() => this.git(["reset", "-q", "--", item.file.path]), `Unstaged ${item.file.path}`);
			} else {
				void this.runOp(
					() => this.applyHunk(item, true),
					`Unstaged hunk ${item.hunkIndex + 1} in ${item.file.path}`,
				);
			}
			return;
		}
		if (item.kind === "file" && item.section === "staged") {
			void this.runOp(() => this.git(["reset", "-q", "--", item.file.path]), `Unstaged ${item.file.path}`);
			return;
		}
		this.notify("Nothing to unstage here", "info");
	}

	// --- navigation --------------------------------------------------------

	private move(delta: number): void {
		if (this.items.length === 0) return;
		const step = delta >= 0 ? 1 : -1;
		let i = this.selected + delta;
		while (i >= 0 && i < this.items.length && this.items[i].kind === "section") i += step;
		if (i < 0) i = 0;
		if (i >= this.items.length) i = this.items.length - 1;
		if (this.items[i].kind === "section") return;
		if (i !== this.selected) {
			this.selected = i;
			this.previewOffset = 0;
			this.bump();
		}
	}

	private jumpTo(i: number): void {
		if (this.items.length === 0) return;
		let idx = i < 0 ? 0 : i >= this.items.length ? this.items.length - 1 : i;
		while (idx >= 0 && idx < this.items.length && this.items[idx].kind === "section") idx += i === 0 ? 1 : -1;
		if (idx < 0 || idx >= this.items.length || this.items[idx].kind === "section") return;
		this.selected = idx;
		this.previewOffset = 0;
		this.bump();
	}

	private scrollPreview(delta: number): void {
		this.previewOffset = Math.max(0, this.previewOffset + delta);
		this.bump();
	}

	private listStart(listH: number): number {
		const max = Math.max(0, this.items.length - listH);
		if (this.selected < this.listScroll) this.listScroll = this.selected;
		if (this.selected > this.listScroll + listH - 1) this.listScroll = this.selected - listH + 1;
		this.listScroll = Math.max(0, Math.min(this.listScroll, max));
		return this.listScroll;
	}

	handleInput(data: string): void {
		if (this.busy) return;

		if (matchesKey(data, Key.up) || data === "k") return this.move(-1);
		if (matchesKey(data, Key.down) || data === "j") return this.move(1);
		if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.ctrl("u"))) return this.move(-10);
		if (matchesKey(data, Key.pageDown) || matchesKey(data, Key.ctrl("d"))) return this.move(10);
		if (data === "g") return this.jumpTo(0);
		if (data === "G") return this.jumpTo(this.items.length - 1);
		if (matchesKey(data, Key.left) || data === "[") return this.scrollPreview(-8);
		if (matchesKey(data, Key.right) || data === "]") return this.scrollPreview(8);
		if (matchesKey(data, Key.space) || data === "a" || data === "A" || matchesKey(data, Key.enter)) {
			return this.stage(this.items[this.selected], data === "A");
		}
		if (data === "r" || data === "R") return this.unstage(this.items[this.selected], data === "R");
		if (data === "t") return this.cycleView();
		if (matchesKey(data, Key.ctrl("r"))) {
			void this.forceRefresh();
			return;
		}
		if (matchesKey(data, Key.escape) || data === "q" || data === "Q") {
			this.done(true);
			return;
		}
	}

	// --- rendering ---------------------------------------------------------

	private statusBadge(f: DiffFile): { char: string; color: "success" | "error" | "warning" | "accent" | "muted" } {
		switch (f.status) {
			case "new":
				return { char: "A", color: "success" };
			case "deleted":
				return { char: "D", color: "error" };
			case "renamed":
				return { char: "R", color: "accent" };
			case "mode":
				return { char: "M", color: "warning" };
			case "binary":
				return { char: "B", color: "muted" };
			default:
				return { char: "M", color: "warning" };
		}
	}

	private renderItem(item: Item, width: number): string {
		const t = this.theme;
		const selected = item === this.items[this.selected];
		const marker = selected ? t.fg("accent", "▸ ") : "  ";
		let body: string;
		switch (item.kind) {
			case "section":
				body = t.fg("accent", t.bold(item.title)) + "  " + t.fg("dim", item.subtitle);
				break;
			case "file": {
				const b = this.statusBadge(item.file);
				const rename = item.file.oldPath && item.file.oldPath !== item.file.path ? t.fg("dim", `${item.file.oldPath} → `) : "";
				body = t.fg(b.color, b.char) + "  " + rename + item.file.path;
				break;
			}
			case "hunk":
				body = t.fg("dim", "   ") + t.fg("muted", item.hunk.header);
				break;
			case "untracked":
				body = t.fg("error", "??") + "  " + item.path;
				break;
		}
		if (selected) body = t.bg("selectedBg", body);
		return marker + body;
	}

	private buildPreview(width: number): string[] {
		const t = this.theme;
		const item = this.items[this.selected];
		if (!item) return [t.fg("dim", "No changes")];
		let lines: string[] = [];
		switch (item.kind) {
			case "section":
				lines = [t.fg("dim", "Navigate to a hunk with ↑/↓, then press a to stage or r to unstage.")];
				break;
			case "untracked":
				lines = [
					t.fg("warning", t.bold("?? ") + item.path),
					"",
					t.fg("dim", `Untracked file. Press ${t.bold("a")} to stage the whole file.`),
				];
				break;
			case "hunk": {
				const label =
					item.section === "staged"
						? `Press ${t.bold("r")} to unstage this hunk, ${t.bold("R")} to unstage the whole file`
						: `Press ${t.bold("a")}/${t.bold("space")} to stage this hunk, ${t.bold("A")} to stage the whole file`;
				lines = [
					t.fg("muted", `${item.file.path}  ·  hunk ${item.hunkIndex + 1}/${item.file.hunks.length}`),
					t.fg("accent", item.hunk.header),
					...item.hunk.lines.map((l) => this.diffLine(l)),
					"",
					t.fg("dim", label),
				];
				break;
			}
			case "file": {
				const label =
					item.section === "staged"
						? `Press ${t.bold("R")} to unstage this file`
						: `Press ${t.bold("A")} to stage this file`;
				lines = [
					t.fg("muted", item.file.path),
					...item.file.header.map((h) => t.fg("dim", h)),
					"",
					...item.file.hunks.flatMap((hunk) => [t.fg("accent", hunk.header), ...hunk.lines.map((l) => this.diffLine(l))]),
					"",
					t.fg("dim", label),
				];
				break;
			}
		}
		if (lines.length > MAX_PREVIEW_LINES) {
			lines = lines.slice(0, MAX_PREVIEW_LINES);
			lines.push(t.fg("dim", `… preview truncated (${t.fg("muted", "←/→ to scroll")})`));
		}
		return lines.map((l) => truncateToWidth(l, width));
	}

	private diffLine(l: DiffLine): string {
		const t = this.theme;
		if (l.kind === "add") return t.fg("toolDiffAdded", l.text);
		if (l.kind === "del") return t.fg("toolDiffRemoved", l.text);
		return t.fg("toolDiffContext", l.text);
	}

	private footerHint(): string {
		const viewLabel = this.view === "unstaged" ? "unstaged" : this.view === "staged" ? "staged" : "all";
		return `↑↓/jk move · a/space/enter stage hunk · A stage file · r unstage hunk · R unstage file · t view:${viewLabel} · ←/→ scroll · ctrl+r refresh · q quit`;
	}

	render(width: number): string[] {
		if (width === this.cachedWidth && this.version === this.cachedVersion) return this.cachedLines;
		const t = this.theme;
		const rows = this.tui.terminal.rows || 24;
		const totalH = Math.max(14, rows - 3);
		const lines: string[] = [];

		// Header
		let head = t.fg("accent", t.bold("Git diff")) + "  " + t.fg("dim", this.countSummary());
		if (this.busy) head += "  " + t.fg("warning", "working…");
		if (this.error) head += "  " + t.fg("error", truncateToWidth(this.error, Math.max(10, Math.floor(width * 0.4)), ""));
		lines.push(truncateToWidth(head, width));

		if (this.items.length === 0) {
			lines.push("");
			lines.push(t.fg("dim", "No changes to show."));
			lines.push("");
			lines.push("");
			lines.push(t.fg("dim", this.footerHint()));
			this.cachedWidth = width;
			this.cachedVersion = this.version;
			this.cachedLines = lines;
			return lines;
		}

		// List
		const listH = Math.max(6, Math.min(this.items.length, Math.floor((totalH - 4) * 0.45)));
		const start = this.listStart(listH);
		for (let r = 0; r < listH; r++) {
			const idx = start + r;
			if (idx >= this.items.length) {
				lines.push("");
				continue;
			}
			lines.push(truncateToWidth(this.renderItem(this.items[idx], width), width));
		}

		// Separator
		lines.push(t.fg("dim", "─".repeat(Math.max(1, Math.min(width, 80)))));

		// Preview
		const pH = totalH - 3 - listH;
		const preview = this.buildPreview(width);
		const pStart = Math.min(this.previewOffset, Math.max(0, preview.length - pH));
		for (let r = 0; r < pH; r++) {
			const idx = pStart + r;
			if (idx >= preview.length) {
				lines.push("");
				continue;
			}
			lines.push(preview[idx]);
		}

		// Footer
		lines.push(t.fg("dim", this.footerHint()));

		this.cachedWidth = width;
		this.cachedVersion = this.version;
		this.cachedLines = lines;
		return lines;
	}
}

// ---------------------------------------------------------------------------
// Command
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.registerCommand("diff", {
		description: "Inspect git changes and stage/unstage hunks interactively",
		getArgumentCompletions: (prefix: string) => {
			const opts = ["--staged", "--cached", "--all"];
			const items = opts.map((o) => ({ value: o, label: o }));
			const filtered = items.filter((i) => i.value.startsWith(prefix));
			return filtered.length > 0 ? filtered : null;
		},
		handler: async (rawArgs, ctx) => {
			const args = (rawArgs ?? "").trim().split(/\s+/).filter(Boolean);
			let view: ViewMode = "unstaged";
			const paths: string[] = [];
			for (const a of args) {
				if (a === "--staged" || a === "--cached") view = "staged";
				else if (a === "--all") view = "all";
				else paths.push(a);
			}

			const gitRun = (gitArgs: string[]): Promise<ExecResult> =>
				pi.exec("git", gitArgs, { cwd: ctx.cwd });

			const root = await gitRun(["rev-parse", "--show-toplevel"]);
			if (root.code !== 0) {
				ctx.ui.notify("Not inside a git repository", "error");
				return;
			}
			const repoRoot = root.stdout.trim();
			const git = (gitArgs: string[]): Promise<ExecResult> => pi.exec("git", gitArgs, { cwd: repoRoot });

			const base = ["-c", "core.quotepath=false"];
			const pathArgs = paths.length > 0 ? ["--", ...paths] : [];

			const fetchState = async (): Promise<DiffState> => {
				const [unstagedRes, stagedRes, untrackedRes] = await Promise.all([
					git([...base, "diff", "--no-color", ...pathArgs]),
					git([...base, "diff", "--cached", "--no-color", ...pathArgs]),
					git([...base, "ls-files", "--others", "--exclude-standard", "-z", ...pathArgs]),
				]);
				return {
					unstaged: parseDiff(unstagedRes.stdout),
					staged: parseDiff(stagedRes.stdout),
					untracked: untrackedRes.stdout.split("\0").filter(Boolean),
				};
			};

			if (ctx.mode !== "tui") {
				// Non-interactive fallback: print the diff.
				const state = await fetchState();
				let out = "";
				for (const f of state.unstaged) out += f.header.join("\n") + "\n" + f.hunks.map((h) => h.header + "\n" + h.lines.map((l) => l.text).join("\n")).join("\n") + "\n";
				if (state.staged.length) {
					out += (out ? "\n" : "") + "# Staged changes\n";
					for (const f of state.staged) out += f.header.join("\n") + "\n" + f.hunks.map((h) => h.header + "\n" + h.lines.map((l) => l.text).join("\n")).join("\n") + "\n";
				}
				if (state.untracked.length) out += (out ? "\n" : "") + "# Untracked files\n" + state.untracked.map((p) => "  " + p).join("\n");
				console.log(out.trim() || "(no changes)");
				ctx.ui.notify("/diff requires interactive mode for hunk staging; printed diff to stdout", "info");
				return;
			}

			const initial = await fetchState();
			await ctx.ui.custom<boolean>((tui, theme, _kb, done) => {
				const viewer = new DiffViewer({
					tui,
					theme,
					done,
					git,
					fetchState,
					view,
					initial,
					notify: (message, kind) => ctx.ui.notify(message, kind ?? "info"),
				});
				return {
					render: (w) => viewer.render(w),
					invalidate: () => viewer.invalidate(),
					handleInput: (data) => {
						viewer.handleInput(data);
						tui.requestRender();
					},
					dispose: () => viewer.invalidate(),
				};
			});
		},
	});
}
