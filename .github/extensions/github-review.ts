/**
 * `create_pull_request_review` tool for the PR review pipeline.
 *
 * Replaces the tool previously provided by shaftoe/pi-coding-agent-action so
 * the pipeline can run `pi` directly (no action = no leaked final comment).
 *
 * Requires, at execution time:
 *   - `gh` CLI (preinstalled on GitHub runners)
 *   - env: `GH_TOKEN`, `REPO` (owner/name), `PR_NUMBER`
 */

import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const createReviewTool = defineTool({
	name: "create_pull_request_review",
	label: "Create Pull Request Review",
	description:
		"Create a pull request review (event COMMENT) with inline comments anchored to specific diff lines.",
	parameters: Type.Object({
		pull_number: Type.Optional(Type.Union([Type.Integer(), Type.Null()])),
		body: Type.Optional(Type.Union([Type.String(), Type.Null()])),
		event: Type.Optional(
			Type.Union([
				Type.Literal("COMMENT"),
				Type.Literal("APPROVE"),
				Type.Literal("REQUEST_CHANGES"),
			])
		),
		comments: Type.Array(
			Type.Object({
				path: Type.String({ description: "File path relative to the repo root" }),
				line: Type.Integer({ description: "Line number in the diff (RIGHT side)" }),
				side: Type.Optional(
					Type.Union([Type.Literal("LEFT"), Type.Literal("RIGHT"), Type.Null()])
				),
				start_line: Type.Optional(Type.Union([Type.Integer(), Type.Null()])),
				start_side: Type.Optional(
					Type.Union([Type.Literal("LEFT"), Type.Literal("RIGHT"), Type.Null()])
				),
				body: Type.String({ description: "Markdown body of the comment" }),
			})
		),
	}),

	async execute(_toolCallId: string, params: any, _signal: unknown, _onUpdate: unknown, _ctx: unknown) {
		const repo = process.env.REPO || "";
		const pr = params.pull_number ?? Number(process.env.PR_NUMBER || 0);
		if (!repo || !pr) {
			return {
				content: [{ type: "text", text: "Missing REPO/PR_NUMBER environment." }],
				details: {},
			};
		}

		const payload: Record<string, unknown> = {
			event: params.event ?? "COMMENT",
			body: params.body ?? "",
			comments: (params.comments ?? []).map((c: any) => {
				const o: Record<string, unknown> = { path: c.path, line: c.line, body: c.body };
				if (c.side) o.side = c.side;
				if (c.start_line) o.start_line = c.start_line;
				if (c.start_side) o.start_side = c.start_side;
				return o;
			}),
		};

		const fs = await import("node:fs");
		const os = await import("node:os");
		const path = await import("node:path");
		const { execSync } = await import("node:child_process");

		const tmp = path.join(os.tmpdir(), `pi-review-${Date.now()}-${Math.random().toString(36).slice(2)}.json`);
		fs.writeFileSync(tmp, JSON.stringify(payload));
		try {
			const out = execSync(
				`gh api "repos/${repo}/pulls/${pr}/reviews" --input "${tmp}" --jq '{id: .id, url: .html_url}'`,
				{ encoding: "utf8", env: { ...process.env } }
			);
			return {
				content: [{ type: "text", text: `Review created: ${out.trim()}` }],
				details: {},
			};
		} catch (e: any) {
			return {
				content: [{ type: "text", text: `Failed to create review: ${e.message}` }],
				details: { error: String(e.stderr || e) },
			};
		} finally {
			try {
				fs.unlinkSync(tmp);
			} catch {
				/* best effort */
			}
		}
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(createReviewTool);
}
