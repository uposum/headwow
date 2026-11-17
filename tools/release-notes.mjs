#!/usr/bin/env node
// Writes a release's notes (Markdown) to stdout.
//
//   node tools/release-notes.mjs --version <full version> --stats <stats.json> --data <data commit>
//                                [--previous <previous release notes .md>]
//
// The notes end with a hidden marker holding this release's addon version, data and code
// commits and counts. The release workflow reads the latest release's marker to skip runs
// where nothing changed, and this script reads it to show what changed since then.

import fs from "node:fs";
import { execFileSync } from "node:child_process";

const MARKER = /<!-- headwow-release (\{.*?\}) -->/;

function option(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
}

export function readMarker(body) {
  const match = MARKER.exec(body ?? "");
  if (!match) return null;
  try { return JSON.parse(match[1]); } catch { return null; }
}

const git = (...args) => execFileSync("git", args, { encoding: "utf8" }).trim();
const number = (n) => n.toLocaleString("en-US");

function delta(now, before) {
  if (before === undefined || before === null) return "";
  const d = now - before;
  if (d === 0) return "no change";
  return (d > 0 ? "+" : "−") + number(Math.abs(d));
}

function snapshotText(iso) {
  if (!iso) return "an unknown date";
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return iso;
  const day = date.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });
  const time = date.toISOString().slice(11, 16);
  return `${day} (scraped ${time} UTC)`;
}

// Commits that touched the addon since the previous release's code commit.
function addonChanges(previousCode) {
  if (!previousCode) return null;
  try {
    git("merge-base", "--is-ancestor", previousCode, "HEAD");
  } catch {
    return null; // unknown or unrelated commit (e.g. history rewritten)
  }
  const log = git("log", "--no-merges", "--format=%s", `${previousCode}..HEAD`, "--", "HeadWow", "HeadWow_Drops", "VERSION");
  return log ? log.split("\n") : [];
}

const version = option("version");
const statsFile = option("stats");
const data = option("data");
if (!version || !statsFile || !data) {
  console.error("usage: node tools/release-notes.mjs --version <v> --stats <stats.json> --data <sha> [--previous <notes.md>]");
  process.exit(1);
}
const stats = JSON.parse(fs.readFileSync(statsFile, "utf8"));
const previousFile = option("previous");
const previous = previousFile && fs.existsSync(previousFile) ? readMarker(fs.readFileSync(previousFile, "utf8")) : null;
const code = git("rev-parse", "HEAD");
const addonVersion = fs.readFileSync("VERSION", "utf8").trim();
const changes = addonChanges(previous?.code);

const lines = [];
lines.push(`Built with the Wowhead snapshot of **${snapshotText(stats.snapshot)}**.`, "");
const rows = [["Items", "items"], ["NPCs", "npcs"], ["Drop tables", "drops"], ["Items with other sources", "sources"], ["NPCs with spawn points", "spawns"]]
  .filter(([, key]) => typeof stats[key] === "number");
if (previous) {
  lines.push("| | Count | Since the last release |", "|---|---:|---:|");
  for (const [label, key] of rows) lines.push(`| ${label} | ${number(stats[key])} | ${delta(stats[key], previous[key])} |`);
} else {
  lines.push("| | Count |", "|---|---:|");
  for (const [label, key] of rows) lines.push(`| ${label} | ${number(stats[key])} |`);
}
lines.push("");

lines.push("### Addon changes");
if (changes === null) lines.push(previous ? "See the commit history." : "First release.");
else if (changes.length === 0) lines.push("None: this release only updates the data.");
else for (const subject of changes) lines.push(`- ${subject}`);
lines.push("");

lines.push("### Install or update");
lines.push(`1. Download **HeadWow-${version}.zip** below.`);
lines.push("2. Extract it into `World of Warcraft/_forever_/Interface/AddOns/`. It holds two folders, `HeadWow` and `HeadWow_Drops`; replace the old ones.");
lines.push("3. Restart the game (a `/reload` doesn't pick up new files).");
lines.push("");

const marker = { version: addonVersion, data, code, items: stats.items, npcs: stats.npcs, drops: stats.drops, sources: stats.sources, spawns: stats.spawns };
lines.push(`<!-- headwow-release ${JSON.stringify(marker)} -->`);
process.stdout.write(lines.join("\n") + "\n");
