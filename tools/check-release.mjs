#!/usr/bin/env node
// Refuses a release whose data shrank against the latest release's (a broken snapshot or a
// converter bug), before anything is published.
//
//   node tools/check-release.mjs <stats.json from convert.mjs> <previous release notes.md>
//
// The previous counts come from the marker at the end of the latest release's notes (see
// tools/release-notes.mjs). No previous release, or no marker: nothing to compare, passes.

import fs from "node:fs";

const [statsPath, previousPath] = process.argv.slice(2);
if (!statsPath || !previousPath) {
  console.error("usage: node tools/check-release.mjs <stats.json> <previous.md>");
  process.exit(1);
}

// Largest allowed drop, as a fraction of the latest release's count.
const ALLOWANCE = { items: 0.02, drops: 0.03, npcs: 0.05 };

const now = JSON.parse(fs.readFileSync(statsPath, "utf8"));
const notes = fs.existsSync(previousPath) ? fs.readFileSync(previousPath, "utf8") : "";
const marker = /<!-- headwow-release (\{.*?\}) -->/.exec(notes);
if (!marker) {
  console.log("No previous release to compare with.");
  process.exit(0);
}
const before = JSON.parse(marker[1]);

const problems = [];
for (const [key, allowed] of Object.entries(ALLOWANCE)) {
  const a = before[key];
  const b = now[key];
  if (typeof a !== "number" || typeof b !== "number" || a <= 0) continue;
  const change = (b - a) / a;
  const line = `${key}: ${a} -> ${b} (${change >= 0 ? "+" : ""}${(change * 100).toFixed(1)}%)`;
  if (change < -allowed) problems.push(`${line}, more than the allowed -${allowed * 100}%`);
  else console.log(line);
}
if (problems.length) {
  for (const p of problems) console.log(`::error::${p}`);
  console.log("Not released. If the drop is deliberate, run the workflow by hand with force on.");
  process.exit(1);
}
console.log("Counts look right.");
