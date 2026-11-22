#!/usr/bin/env node
// HeadWow's tests, outside the game (Lua runs in fengari):
//
//   logic    the data modules (search, NPCs, where to farm, wishlist, gold farming, AH market)
//            against a tiny snapshot, with hand-checked numbers
//   convert  tools/convert.mjs on a tiny snapshot in the scraper's format, the generated Lua checked
//   smoke    the whole addon, loaded in TOC order into a mock client (tests/mock/wow.lua):
//            opens every view, clicks and hovers every row, card, tab, menu entry and button,
//            runs the slash commands, map pins, tooltips and loot alert, and fails on any error
//
//   node tests/run.mjs
//   SMOKE_TRACE="card row" node tests/run.mjs   also print the smoke steps whose name contains that text

import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { newLua, coreName } from "./lib/lua.mjs";
import { templatesLua } from "./lib/templates.mjs";
import { writeSnapshot } from "./convert/snapshot.mjs";

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
  for (const f of ["Search.lua", "NPC.lua", "Farm.lua", "Wishlist.lua", "GoldFarm.lua", "Vendors.lua"]) runFile(path.join(addon, f), f);
  runFile(path.join(here, "logic", "checks.lua"), "checks.lua");
});

// tools/convert.mjs on a tiny schema 2 snapshot, then the generated Lua loaded and checked.
suite("convert", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "headwow-convert-"));
  try {
    writeSnapshot(path.join(tmp, "snapshot"));
    const out = path.join(tmp, "addon");
    const res = spawnSync(process.execPath, [path.join(here, "..", "tools", "convert.mjs"), path.join(tmp, "snapshot"), out], { encoding: "utf8" });
    if (res.status !== 0) throw new Error(`convert.mjs failed:\n${res.stderr}`);
    const { run, runFile } = newLua();
    run("HeadWowData = { items = {}, npcs = {}, npcLevels = {}, npcTags = {}, npcReact = {}, zones = {}, zoneMaps = {}, slots = {}, "
      + "drops = {}, sources = {}, spawns = {}, objects = {}, quests = {}, spells = {} }", "init");
    for (const dir of [path.join(out, "HeadWow", "Data", "Generated"), path.join(out, "HeadWow_Drops", "Generated")]) {
      const xml = fs.readFileSync(path.join(dir, "Data.xml"), "utf8");
      for (const [, file] of xml.matchAll(/<Script file="([^"]+)"/g)) runFile(path.join(dir, file), file);
    }
    runFile(path.join(here, "convert", "checks.lua"), "convert/checks.lua");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

suite("smoke", () => {
  const { run, runFile } = newLua();
  run("REAL_PRINT = print; SMOKE_TRACE = " + JSON.stringify(process.env.SMOKE_TRACE ?? null).replace("null", "nil"), "init");
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
