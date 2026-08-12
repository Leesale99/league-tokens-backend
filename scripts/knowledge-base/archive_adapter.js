"use strict";

/*
 * Obsidian-side adapter for the deterministic archive_inventory.py payload.
 *
 * This module never writes to the filesystem. The caller must execute it inside
 * `obsidian eval`, passing the live Obsidian `app`; all vault writes go through
 * `app.vault`. The payload itself is read outside model context.
 */

const fs = require("fs");
const crypto = require("crypto");

function quote(value) {
  return JSON.stringify(String(value));
}

function safePart(value) {
  if (!value || value === "." || value === ".." || value.includes("\\") || value.includes("\0")) {
    throw new Error(`unsafe archive path component: ${value}`);
  }
  return value;
}

function safeRelativePath(value) {
  const parts = String(value).split("/").map(safePart);
  if (parts.some(part => part === "")) throw new Error(`unsafe archive path: ${value}`);
  return parts.join("/");
}

async function ensureFolder(app, folder) {
  const parts = folder.split("/").filter(Boolean);
  let current = "";
  for (const part of parts) {
    current = current ? `${current}/${part}` : part;
    if (!app.vault.getAbstractFileByPath(current)) {
      await app.vault.createFolder(current);
    }
  }
}

async function writeNote(app, path, content) {
  await ensureFolder(app, path.split("/").slice(0, -1).join("/"));
  const existing = app.vault.getAbstractFileByPath(path);
  if (existing) await app.vault.modify(existing, content);
  else await app.vault.create(path, content);
}

function frontmatter(fields) {
  return `---\n${Object.entries(fields).map(([key, value]) => `${key}: ${quote(value)}`).join("\n")}\n---\n`;
}

function decodeArtifact(artifact) {
  if (artifact.content_encoding !== "base64" || !artifact.content_base64) {
    throw new Error(`payload does not contain content for ${artifact.source_path}`);
  }
  return Buffer.from(artifact.content_base64, "base64");
}

function renderedBody(artifact, data) {
  const text = data.toString("utf8");
  if (artifact.media_type === "application/json" || artifact.source_path.endsWith(".json")) {
    return `\n\n## Artifact content\n\n\`\`\`json\n${text.replace(/```/g, "```\\u200b")}\n\`\`\`\n`;
  }
  if (artifact.media_type.startsWith("text/") || artifact.source_path.endsWith(".md")) {
    return `\n\n## Artifact content\n\n${text}`;
  }
  return `\n\n## Artifact content\n\n\`\`\`text\n${data.toString("base64")}\n\`\`\`\n`;
}

async function archiveFromPayload(app, payloadPath, options = {}) {
  const payload = JSON.parse(fs.readFileSync(payloadPath, "utf8"));
  if (payload.schema !== 1 || payload.content_included !== true) {
    throw new Error("archive payload must be schema 1 with content_included=true");
  }
  if (!Number.isInteger(payload.issue_number) || payload.issue_number <= 0) {
    throw new Error("archive payload has an invalid issue_number");
  }
  if (!Array.isArray(payload.artifacts) || payload.artifacts.length !== payload.artifact_count) {
    throw new Error("archive payload artifact_count does not match artifacts");
  }

  const issue = String(payload.issue_number);
  const year = String(options.year || new Date().getUTCFullYear());
  const title = safePart(options.shortTitle || `Issue ${issue}`);
  const root = `60 Issue Archive/${year}/Issue ${issue} – ${title}`;
  const artifactRoot = `${root}/Artifacts`;
  const branch = options.vaultBranch || "kb/archive/issue-" + issue;
  const stage = options.archiveStage || "prepared";
  const artifactLinks = [];
  const manifestRows = [];

  for (const artifact of payload.artifacts) {
    const relative = safeRelativePath(artifact.relative_path);
    const destination = `${artifactRoot}/${relative.endsWith(".md") ? relative : `${relative}.md`}`;
    const data = decodeArtifact(artifact);
    const actualHash = crypto.createHash("sha256").update(data).digest("hex");
    if (actualHash !== artifact.source_hash || data.length !== artifact.source_byte_count) {
      throw new Error(`payload integrity mismatch for ${artifact.source_path}`);
    }
    const metadata = frontmatter({
      kind: "issue-artifact",
      status: "archived",
      issue_number: issue,
      archive_stage: stage,
      source_path: artifact.source_path,
      source_byte_count: artifact.source_byte_count,
      source_hash: artifact.source_hash,
      media_type: artifact.media_type,
    });
    await writeNote(app, destination, metadata + `\n## Provenance\n\nOriginal repository path: ${artifact.source_path}\n\n` + renderedBody(artifact, data));
    artifactLinks.push(`- [[${destination}]]`);
    manifestRows.push(`| ${artifact.source_path} | ${destination} | ${artifact.source_byte_count} | ${artifact.source_hash} | ${artifact.media_type} | verified |`);
  }

  const manifest = [
    `# Archive Manifest — Issue ${issue}`,
    "",
    "## Publication state",
    "",
    `- archive_stage: ${stage}`,
    `- vault_pr: ${options.vaultPr || "pending"}`,
    `- vault_merge_commit: ${options.vaultMergeCommit || "pending"}`,
    `- backend_cleanup_pr: ${options.backendCleanupPr || "pending"}`,
    "",
    "## Artifacts",
    "",
    "| Source path | Vault destination | Source bytes | Source SHA-256 | Media type | Verification |",
    "| --- | --- | ---: | --- | --- | --- |",
    ...manifestRows,
    "",
  ].join("\n");
  const manifestHash = crypto.createHash("sha256").update(manifest).digest("hex");
  await writeNote(app, `${root}/Manifest.md`, frontmatter({ kind: "issue-manifest", status: "verified", issue_number: issue, archive_stage: stage, artifact_count: payload.artifact_count, vault_pr: options.vaultPr || "pending", vault_merge_commit: options.vaultMergeCommit || "pending", backend_cleanup_pr: options.backendCleanupPr || "pending", manifest_hash: manifestHash }) + manifest);

  const landing = [
    frontmatter({
      kind: "issue-archive",
      status: "archived",
      issue_number: issue,
      issue_state: "CLOSED",
      archive_stage: stage,
      issue_url: options.issueUrl || "pending",
      closed_at: options.closedAt || "pending",
      source_branch: payload.source_branch || "unknown",
      source_revision: payload.source_revision,
      vault_branch: branch,
      vault_pr: options.vaultPr || "pending",
      vault_merge_commit: options.vaultMergeCommit || "pending",
      backend_cleanup_pr: options.backendCleanupPr || "pending",
      manifest_hash: manifestHash,
    }),
    `# Issue ${issue} — ${title}`,
    "",
    "## Summary",
    "",
    `Issue: [#${issue}](${options.issueUrl || "pending"})`,
    `Closed at: ${options.closedAt || "pending"}`,
    "",
    "## Artifacts",
    "",
    ...artifactLinks,
    "- [[Manifest]]",
    "",
    "## Publication state",
    "",
    `- archive_stage: ${stage}`,
    `- vault_pr: ${options.vaultPr || "pending"}`,
    `- vault_merge_commit: ${options.vaultMergeCommit || "pending"}`,
    `- backend_cleanup_pr: ${options.backendCleanupPr || "pending"}`,
    `- manifest_hash: ${manifestHash}`,
    "",
  ].join("\n");
  await writeNote(app, `${root}/Issue ${issue} – ${title}.md`, landing);

  return JSON.stringify({ issue_number: payload.issue_number, root, artifact_count: payload.artifact_count, manifest_hash: manifestHash, archive_stage: stage });
}

module.exports = { archiveFromPayload };
