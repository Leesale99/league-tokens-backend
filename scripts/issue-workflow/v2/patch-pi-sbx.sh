#!/usr/bin/env bash
# Idempotently re-applies the pi-sbx "host-only tools" patch to the installed
# @christianmoesl/pi-sbx package. Run after any reinstall/update of the package
# (e.g. `pi update` or npm reinstall), otherwise extension tools (obsidian,
# context7, pi-web-access) are blocked again by pi-sbx's ROUTED_TOOLS guard
# with "Tool X is not sandbox-aware and cannot run in the selected sbx sandbox."
#
# What the patch does: reads PI_SBX_HOST_TOOLS (comma-separated tool names) and
# skips the sandbox guard for those tools. Extension tool execute() already runs
# in the pi process on the HOST, so unblocking is sufficient — no wrapper needed.
#
# SECURITY: tools on PI_SBX_HOST_TOOLS run host-side with host permissions and
# WITHOUT per-call approval. Only list tools that inherently need the host
# (obsidian CLI + vault, network tools using host credentials).
#
# Usage: patch-pi-sbx.sh [--check]
#   --check   print whether the patch is currently applied; exit 0/1.

set -euo pipefail

PKG_DIR="${PI_SBX_PKG_DIR:-$HOME/.pi/agent/npm/node_modules/@christianmoesl/pi-sbx}"
TARGET="$PKG_DIR/extensions/pi-sbx/index.ts"

[[ -f "$TARGET" ]] || {
  echo "patch-pi-sbx: pi-sbx not found at $TARGET (set PI_SBX_PKG_DIR)" >&2
  exit 1
}

if [[ "${1:-}" == "--check" ]]; then
  if grep -q "HOST_ONLY_TOOLS" "$TARGET"; then
    echo "patch-pi-sbx: applied"
    exit 0
  fi
  echo "patch-pi-sbx: NOT applied"
  exit 1
fi

if grep -q "HOST_ONLY_TOOLS" "$TARGET"; then
  echo "patch-pi-sbx: already applied — nothing to do"
  exit 0
fi

node - "$TARGET" <<'NODE'
const fs = require("fs");
const path = process.argv[2];
let src = fs.readFileSync(path, "utf8");

const routedLine = 'const ROUTED_TOOLS = new Set(["bash", "edit", "find", "grep", "ls", "read", "write"]);';
const hostOnlyBlock = `const ROUTED_TOOLS = new Set(["bash", "edit", "find", "grep", "ls", "read", "write"]);

// Host-only tools: extension tools whose execute runs in the pi process (host),
// e.g. the obsidian CLI tool, context7, pi-web-access. They can never execute
// inside the sandbox (no CLI binary / vault / credentials there), and unblocking
// them makes them run on the host — no wrapper needed. Configure via
// PI_SBX_HOST_TOOLS (env, comma-separated) and/or ~/.pi/agent/sbx-host-tools
// (one tool name per line, or comma-separated). Security: tools on this list
// run host-side with host permissions and WITHOUT per-call approval.
const HOST_ONLY_TOOLS = new Set([
\t...(process.env.PI_SBX_HOST_TOOLS ?? "")
\t\t.split(",")
\t\t.map((s) => s.trim())
\t\t.filter(Boolean),
\t...(function () {
\t\t// Also read ~/.pi/agent/sbx-host-tools (one tool name per line, or comma
\t\t// separated) so the config works regardless of how pi is launched — a
\t\t// shell env var is lost when pi is started from a GUI/app context.
\t\ttry {
\t\t\treturn require("node:fs")
\t\t\t\t.readFileSync(\`\${process.env.HOME}/.pi/agent/sbx-host-tools\`, "utf8")
\t\t\t\t.split(/[\\s,]+/)
\t\t\t\t.map((s) => s.trim())
\t\t\t\t.filter(Boolean);
\t\t} catch {
\t\t\treturn [];
\t\t}
\t})(),
]);`;
const hookOld = 'if (!ROUTED_TOOLS.has(event.toolName)) {';
const hookNew = 'if (!ROUTED_TOOLS.has(event.toolName) && !HOST_ONLY_TOOLS.has(event.toolName)) {';

if (!src.includes(routedLine)) {
  console.error("patch-pi-sbx: ROUTED_TOOLS line not found — package layout changed?");
  process.exit(1);
}
if (!src.includes(hookOld)) {
  console.error("patch-pi-sbx: tool_call guard not found — package layout changed?");
  process.exit(1);
}

src = src.replace(routedLine, hostOnlyBlock);
src = src.replace(hookOld, hookNew);
fs.writeFileSync(path, src);
console.log("patch-pi-sbx: applied");
NODE

# Note: takes effect on the NEXT pi start (/reload only hot-reloads extensions
# in auto-discovered locations, not npm packages).
echo "patch-pi-sbx: done — restart pi (or /reload if it picks up packages) for it to take effect."
