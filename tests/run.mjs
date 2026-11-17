#!/usr/bin/env node
// HeadWow's tests, outside the game (Lua runs in fengari):
//
//   logic  the data modules (search, NPCs, where to farm, wishlist, gold farming, AH market)
//          against a tiny snapshot, with hand-checked numbers
//   smoke  the whole addon, loaded in TOC order into a mock client (tests/mock/wow.lua):
//          opens every view, clicks and hovers every row, card, tab, menu entry and button,
//          runs the slash commands, map pins, tooltips and loot alert, and fails on any error
//
//   node tests/run.mjs

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { newLua, coreName } from "./lib/lua.mjs";
import { templatesLua } from "./lib/templates.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const addon = path.resolve(here, "..", "HeadWow");
const failures = [];

function suite(name, fn) {
  try {
    fn();
  } catch (err) {
    failures.push(name);
    console.error(`${name}: ${err.message}`);
  }
}

suite("logic", () => {
  const { runFile } = newLua();
  runFile(path.join(here, "logic", "mocks.lua"), "mocks.lua");
  runFile(path.join(addon, "Core.lua"), "Core.lua", coreName);
  runFile(path.join(here, "logic", "data.lua"), "data.lua");
  for (const f of ["Search.lua", "NPC.lua", "Farm.lua", "Wishlist.lua", "GoldFarm.lua"]) runFile(path.join(addon, f), f);
  runFile(path.join(here, "logic", "checks.lua"), "checks.lua");
});

suite("smoke", () => {
  const { run, runFile } = newLua();
  run("REAL_PRINT = print", "init");
  run(templatesLua(path.join(addon, "UI", "Templates.xml")), "templates");
  runFile(path.join(here, "mock", "wow.lua"), "wow.lua");
  // Every Lua file in TOC order; the generated data is replaced by tests/smoke/data.lua.
  const toc = fs.readFileSync(path.join(addon, "HeadWow.toc"), "utf8").split(/\r?\n/).filter((l) => l.trim() && !l.startsWith("#"));
  for (const entry of toc) {
    if (entry.endsWith(".xml")) continue;
    const file = entry.replaceAll("\\", "/");
    runFile(path.join(addon, file), file, file === "Core.lua" ? coreName : undefined);
    if (file === "Core.lua") runFile(path.join(here, "smoke", "data.lua"), "smoke/data.lua");
  }
  runFile(path.join(here, "smoke", "driver.lua"), "driver.lua");
});

if (failures.length) {
  console.error(`failed: ${failures.join(", ")}`);
  process.exit(1);
}
