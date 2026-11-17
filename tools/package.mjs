#!/usr/bin/env node
// Packages HeadWow + HeadWow_Drops into dist/ (and a zip if `zip` is available).
//
//   node tools/package.mjs [version]

import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const version = process.argv[2] ?? new Date().toISOString().slice(0, 10).replaceAll("-", ".");
const dist = path.join(root, "dist");
const addons = ["HeadWow", "HeadWow_Drops"];

if (!fs.existsSync(path.join(root, "HeadWow", "Data", "Generated", "Data.xml"))) {
  console.error("Generated data missing. Run: node tools/convert.mjs <path-to-wow-forever-data>");
  process.exit(1);
}

fs.rmSync(dist, { recursive: true, force: true });
for (const addon of addons) {
  const dest = path.join(dist, addon);
  fs.cpSync(path.join(root, addon), dest, { recursive: true });
  for (const f of fs.readdirSync(dest).filter((f) => f.endsWith(".toc"))) {
    const p = path.join(dest, f);
    fs.writeFileSync(p, fs.readFileSync(p, "utf8").replaceAll("@project-version@", version));
  }
}

const zipName = `HeadWow-${version}.zip`;
try {
  execSync(`zip -qr ${zipName} ${addons.join(" ")}`, { cwd: dist, stdio: "inherit" });
  console.log(`dist/${zipName}`);
} catch {
  console.log(`Copied addons to dist/ (zip not available, skipped ${zipName}).`);
}
