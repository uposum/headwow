#!/usr/bin/env node
// Static checks over both addons:
//   - every .lua file parses as Lua 5.1 (the game's dialect), generated data included
//   - every .xml file is well-formed
//   - no global read of a name the same file declares as a local: a local function used
//     above its definition, which is nil at runtime (the classic "attempt to call a nil
//     value" that only shows up in game)
//
//   node tools/lint.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";
import { XMLValidator } from "fast-xml-parser";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const addons = ["HeadWow", "HeadWow_Drops"];
const problems = [];
let checked = 0;

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const name of fs.readdirSync(dir)) {
    const p = path.join(dir, name);
    if (fs.statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// Names read as globals that the file also declares as locals.
function useBeforeLocal(ast) {
  const globals = [];
  const locals = new Set();
  (function visit(node) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) return node.forEach(visit);
    if (node.type === "Identifier" && node.isLocal === false) globals.push(node);
    if (node.type === "LocalStatement") node.variables.forEach((v) => locals.add(v.name));
    if (node.type === "FunctionDeclaration" && node.isLocal && node.identifier) locals.add(node.identifier.name);
    for (const key of Object.keys(node)) if (key !== "loc" && key !== "range") visit(node[key]);
  })(ast.body);
  return globals.filter((g) => locals.has(g.name));
}

for (const addon of addons) {
  for (const file of walk(path.join(root, addon))) {
    const rel = path.relative(root, file).replaceAll("\\", "/");
    const generated = rel.includes("/Generated/");
    if (file.endsWith(".lua")) {
      checked++;
      try {
        const ast = luaparse.parse(fs.readFileSync(file, "utf8"), {
          luaVersion: "5.1", scope: !generated, locations: !generated,
        });
        if (!generated) {
          for (const g of useBeforeLocal(ast)) {
            problems.push(`${rel}:${g.loc.start.line}: '${g.name}' is read as a global, but the file declares a local of that name (used before its definition?)`);
          }
        }
      } catch (err) {
        problems.push(`${rel}: ${err.message}`);
      }
    } else if (file.endsWith(".xml")) {
      checked++;
      const result = XMLValidator.validate(fs.readFileSync(file, "utf8"));
      if (result !== true) problems.push(`${rel}:${result.err.line}: ${result.err.msg}`);
    }
  }
}

for (const p of problems) console.error(p);
console.log(`${checked} files checked, ${problems.length} problem${problems.length === 1 ? "" : "s"}`);
process.exit(problems.length ? 1 : 0);
