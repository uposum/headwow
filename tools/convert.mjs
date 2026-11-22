#!/usr/bin/env node
// Converts a wow-forever-data snapshot into the Lua data files bundled with the addon.
//
//   node tools/convert.mjs <path-to-wow-forever-data> [addon-root] [--stats <file.json>]
//
// Reads schema 2 snapshots (data/manifest.json + JSONL files, see the scraper's
// src/snapshot.ts) and, for older releases, schema 1 (data/items.json).
// --stats writes the snapshot's counts as JSON, for the release notes and the release check.
//
// Output (all generated, git-ignored):
//   HeadWow/Data/Generated/        Meta.lua, Items_NN.lua, Npcs_NN.lua, NpcInfo_NN.lua, Data.xml
//   HeadWow_Drops/Generated/       Drops_NN.lua, Sources_NN.lua, Spawns_NN.lua, Refs_NN.lua, Data.xml
// The core addon has what search and lists need; the big tables load on demand.
//
// Row formats (1-based Lua arrays, nil = unknown):
//   items[id]     = { name, quality, itemLevel, requiredLevel, slotIdx, sourceMask, sellCopper,
//                     zoneIdx, from, dropRows, buyCopper }
//   npcs[id]      = { name, zoneIdx, zoneIdx, ... }
//   npcLevels[id] = minLevel * 10000 + maxLevel * 10 + rank   (just rank when the level is "??")
//   npcTags[id]   = "General Supplies"
//   npcReact[id]  = (alliance + 2) * 4 + (horde + 2), each 1 friendly, 0 neutral, -1 hostile (a
//                   part is 0 when unknown)
//   zoneMaps[zoneIdx] = uiMapID
//   drops[itemId] = { leftOut, npcId, chanceBasisPoints, samples, stack x100, npcId, ... }
//   sources[itemId] = { kind, id, a, b, c, kind, id, a, b, c, ... }   (every way to get it but drops)
//       kind 1 vendor:           npcId, copper, stock (-1 unlimited), stack bought
//       kind 2 skinned, 3 pickpocketed:                  npcId, chance bp, samples, stack x100
//       kind 4 mined, 5 gathered, 6 in a chest/object:   objectId, chance bp, samples, stack x100
//       kind 7 fished:           zoneIdx, chance bp, samples, stack x100
//       kind 8 in a container item: itemId, chance bp, samples, stack x100
//       kind 9 quest reward:     questId, 0, 0, 0
//       kind 10 crafted:         spellId, 0, 0, 0
//   spawns[npcId] = { uiMapID, count, x*10 * 1000 + y*10, ..., uiMapID, count, ... }
//   objects[id] = { name, zoneIdx, ... }   quests[id] = { name, level }   spells[id] = { name, learnedAt }

import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
const statsAt = args.indexOf("--stats");
const statsPath = statsAt >= 0 ? args[statsAt + 1] : null;
if (statsAt >= 0) args.splice(statsAt, 2);
const [dataRoot, outRootArg] = args;
if (!dataRoot || (statsAt >= 0 && !statsPath)) {
  console.error("usage: node tools/convert.mjs <path-to-wow-forever-data> [addon-root] [--stats <file.json>]");
  process.exit(1);
}
const outRoot = outRootArg ?? path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), "..");
const dataDir = fs.existsSync(path.join(dataRoot, "data")) ? path.join(dataRoot, "data") : dataRoot;

const ROWS_PER_FILE = 4000; // keeps each chunk well below Lua's per-function constant limit

// Drop rows bundled per item: the best TOP_DROPS always, the rest only from MIN_DROP_BP
// (0.05%) up. The smaller ones are counted (leftOut) and the item page says so.
const TOP_DROPS = 25;
const MIN_DROP_BP = 5;
const MAX_SOURCE_ROWS = 25; // per kind and item, best first. Vendors and skinning keep every row: the item
                            // page lists every vendor, nearest first, and gold farming adds up what each mob gives

const QUALITY = { Poor: 0, Common: 1, Uncommon: 2, Rare: 3, Epic: 4, Legendary: 5, Artifact: 6, Heirloom: 7 };
const SOURCE_BITS = { Drop: 1, Vendor: 2, Quest: 4, Crafted: 8, Skinning: 16, Gathering: 32, Container: 64, Fishing: 128, Pickpocket: 256 };
const RANK = { 0: 0, 1: 1, 2: 2, 3: 3, 4: 4 };
const KIND = { soldBy: 1, skinnedFrom: 2, pickpocketedFrom: 3, minedFrom: 4, gatheredFrom: 5, containedInObject: 6, fishedIn: 7, containedInItem: 8, rewardFrom: 9, createdBy: 10 };
const PAGE_BITS = {
  droppedBy: SOURCE_BITS.Drop, soldBy: SOURCE_BITS.Vendor, rewardFrom: SOURCE_BITS.Quest, createdBy: SOURCE_BITS.Crafted,
  skinnedFrom: SOURCE_BITS.Skinning, minedFrom: SOURCE_BITS.Gathering, gatheredFrom: SOURCE_BITS.Gathering,
  containedInObject: SOURCE_BITS.Container, containedInItem: SOURCE_BITS.Container, fishedIn: SOURCE_BITS.Fishing,
  pickpocketedFrom: SOURCE_BITS.Pickpocket,
};

// ---------- helpers ----------
// An NPC's reaction to [Alliance, Horde] from its Wowhead page: 1 friendly, 0 neutral, -1 hostile.
// Wowhead leaves the other faction out for many faction NPCs (Thunder Bluff's are [null, 1]), so
// one friendly to a faction and silent on the other is taken as hostile to it.
function packReaction(react) {
  if (!Array.isArray(react)) return undefined;
  let [a, h] = [react[0], react[1]].map((v) => (v === 1 || v === 0 || v === -1 ? v : null));
  if (a === null && h === 1) a = -1;
  if (h === null && a === 1) h = -1;
  if (a === null && h === null) return undefined;
  return (a === null ? 0 : a + 2) * 4 + (h === null ? 0 : h + 2);
}

function luaStr(s) {
  let out = '"';
  for (const ch of String(s)) {
    const c = ch.codePointAt(0);
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (c < 32 || c === 127) out += "\\" + c;
    else out += ch;
  }
  return out + '"';
}
const luaVal = (v) => (v === undefined || v === null ? "nil" : typeof v === "string" ? luaStr(v) : String(v));
function luaRow(arr) {
  let end = arr.length; // trim trailing nils
  while (end > 0 && (arr[end - 1] === undefined || arr[end - 1] === null)) end--;
  return "{" + arr.slice(0, end).map(luaVal).join(",") + "}";
}
const int = (v) => {
  const n = parseInt(v, 10);
  return Number.isFinite(n) && n > 0 ? n : undefined;
};
function copper(price) {
  if (typeof price === "number") return price > 0 ? Math.round(price) : undefined;
  if (!price) return undefined;
  let total = 0;
  for (const [, n, unit] of String(price).matchAll(/(\d+)\s*([gsc])/g)) {
    total += Number(n) * (unit === "g" ? 10000 : unit === "s" ? 100 : 1);
  }
  return total || undefined;
}
const bp = (pct) => (typeof pct === "number" && pct >= 0 ? Math.round(pct * 100) : -1);
function basisPointsFromText(chance) {
  const m = /^([\d.]+)%$/.exec(chance ?? "");
  return m ? Math.round(parseFloat(m[1]) * 100) : undefined;
}

function makeIndex() {
  const list = [];
  const map = new Map();
  return {
    list,
    idx(value) {
      if (value === undefined || value === null || value === "") return undefined;
      if (!map.has(value)) {
        list.push(value);
        map.set(value, list.length);
      }
      return map.get(value);
    },
  };
}

function writeChunks(dir, prefix, header, rows) {
  const files = [];
  for (let i = 0; i < rows.length; i += ROWS_PER_FILE) {
    const name = `${prefix}_${String(files.length + 1).padStart(2, "0")}.lua`;
    const body = rows.slice(i, i + ROWS_PER_FILE).join("\n");
    fs.writeFileSync(path.join(dir, name), `-- Generated by tools/convert.mjs. Do not edit.\n${header}\n${body}\n`);
    files.push(name);
  }
  return files;
}
function writeXml(dir, files) {
  const scripts = files.map((f) => `\t<Script file="${f}"/>`).join("\n");
  fs.writeFileSync(
    path.join(dir, "Data.xml"),
    `<Ui xmlns="http://www.blizzard.com/wow/ui/">\n<!-- Generated by tools/convert.mjs. Do not edit. -->\n${scripts}\n</Ui>\n`
  );
}
function resetDir(dir) {
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
}
function readJsonl(file) {
  if (!fs.existsSync(file)) return [];
  return fs.readFileSync(file, "utf8").split(/\r?\n/).filter((l) => l.trim()).map((l) => JSON.parse(l));
}

// ---------- shared state ----------
const zones = makeIndex();
const slots = makeIndex();
const itemRows = [];
const dropRows = [];
const sourceRows = [];
const npcUsed = new Set();
const stats = { schema: 1, droppedRowsLeftOut: 0 };

// ---------- schema 2 ----------
function convertSchema2() {
  const manifest = JSON.parse(fs.readFileSync(path.join(dataDir, "manifest.json"), "utf8"));
  const files = manifest.files ?? {};
  const read = (key, dflt) => readJsonl(path.join(dataDir, files[key] ?? dflt));
  const items = read("items", "items.jsonl").sort((a, b) => a.id - b.id);
  const pages = new Map(read("pages", "item-pages.jsonl").map((p) => [p.id, p]));
  const npcs = new Map(read("npcs", "npcs.jsonl").map((n) => [n.id, n]));
  const objects = new Map(read("objects", "objects.jsonl").map((o) => [o.id, o]));
  const quests = new Map(read("quests", "quests.jsonl").map((q) => [q.id, q]));
  const spells = new Map(read("spells", "spells.jsonl").map((s) => [s.id, s]));
  const zoneInfo = JSON.parse(fs.readFileSync(path.join(dataDir, files.zones ?? "zones.json"), "utf8"));
  const zoneIdxOfArea = (area) => {
    const z = zoneInfo[area];
    return z?.name ? zones.idx(z.name) : undefined;
  };
  const usedObjects = new Set();
  const usedQuests = new Set();
  const usedSpells = new Set();

  for (const it of items) {
    const page = pages.get(it.id) ?? {};
    const self = page.self ?? {};
    let mask = 0;
    for (const part of (it.obtainedBy ?? "").split(/,\s*/)) mask |= SOURCE_BITS[part] ?? 0;
    for (const [key, bit] of Object.entries(PAGE_BITS)) if (page[key]?.length) mask |= bit;

    // Drops: the best TOP_DROPS, then everything from MIN_DROP_BP up.
    const drops = page.droppedBy ?? [];
    let kept = 0;
    let leftOut = 0;
    const flat = [0];
    drops.forEach((row, i) => {
      const [npcId, chance, samples, stack] = row;
      const b = bp(chance);
      if (i >= TOP_DROPS && b < MIN_DROP_BP) {
        leftOut++;
        return;
      }
      flat.push(npcId, b, samples ?? 0, Math.round((stack ?? 1) * 100));
      npcUsed.add(npcId);
      kept++;
    });
    flat[0] = leftOut;
    stats.droppedRowsLeftOut += leftOut;
    if (kept) dropRows.push(`R[${it.id}]=${luaRow(flat)}`);

    // Every other way to get it.
    const src = [];
    const addLoot = (key, mapId, limit = MAX_SOURCE_ROWS) => {
      for (const row of (page[key] ?? []).slice(0, limit)) {
        const id = mapId(row[0]);
        if (id === undefined) continue;
        src.push(KIND[key], id, bp(row[1]), row[2] ?? 0, Math.round((row[3] ?? 1) * 100));
      }
    };
    for (const row of page.soldBy ?? []) {
      src.push(KIND.soldBy, row[0], row[1] ?? 0, row[2] ?? -1, row[3] ?? 1);
      npcUsed.add(row[0]);
    }
    addLoot("skinnedFrom", (id) => (npcUsed.add(id), id), Infinity);
    addLoot("pickpocketedFrom", (id) => (npcUsed.add(id), id));
    for (const key of ["minedFrom", "gatheredFrom", "containedInObject"]) addLoot(key, (id) => (usedObjects.add(id), id));
    addLoot("fishedIn", zoneIdxOfArea);
    addLoot("containedInItem", (id) => id);
    for (const q of (page.rewardFrom ?? []).slice(0, MAX_SOURCE_ROWS)) {
      src.push(KIND.rewardFrom, q, 0, 0, 0);
      usedQuests.add(q);
    }
    for (const s of (page.createdBy ?? []).slice(0, MAX_SOURCE_ROWS)) {
      src.push(KIND.createdBy, s, 0, 0, 0);
      usedSpells.add(s);
    }
    if (src.length) sourceRows.push(`S[${it.id}]=${luaRow(src)}`);

    const name = it.origin === "sitemap" ? self.name ?? it.name : it.name ?? self.name;
    itemRows.push(
      `I[${it.id}]=` +
        luaRow([
          name ?? `Item ${it.id}`,
          QUALITY[it.quality ?? self.quality],
          int(it.itemLevel ?? self.itemLevel),
          int(it.requiredLevel ?? self.reqLevel),
          slots.idx(it.slot ?? self.slot),
          mask || undefined,
          copper(it.sellCopper ?? self.sellCopper),
          zones.idx(it.zone),
          it.from,
          kept ? kept + leftOut : undefined,
          copper(self.buyCopper),
        ])
    );
  }

  // NPCs: every one a bundled table points at.
  const npcRows = [];
  const levelRows = [];
  const tagRows = [];
  const reactRows = [];
  const spawnRows = [];
  let withSpawns = 0;
  for (const id of [...npcUsed].sort((a, b) => a - b)) {
    const n = npcs.get(id) ?? {};
    const zoneIdxs = [...new Set((n.zones ?? []).map(zoneIdxOfArea).filter(Boolean))];
    npcRows.push(`N[${id}]=${luaRow([n.name ?? `NPC ${id}`, ...zoneIdxs])}`);
    const rank = RANK[n.classification] ?? 0;
    if (typeof n.minLevel === "number" && n.minLevel > 0) {
      const max = typeof n.maxLevel === "number" && n.maxLevel >= n.minLevel ? n.maxLevel : n.minLevel;
      levelRows.push(`L[${id}]=${n.minLevel * 10000 + Math.min(max, 999) * 10 + rank}`);
    } else if (rank === 3) {
      levelRows.push(`L[${id}]=${rank}`); // a "??" boss
    }
    if (n.tag) tagRows.push(`T[${id}]=${luaStr(n.tag)}`);
    const react = packReaction(n.react);
    if (react !== undefined) reactRows.push(`F[${id}]=${react}`);
    if (n.spawns) {
      const flat = [];
      for (const [mapId, points] of Object.entries(n.spawns)) {
        flat.push(Number(mapId), points.length);
        for (const [x, y] of points) flat.push(Math.round(x * 10) * 1000 + Math.min(999, Math.round(y * 10)));
      }
      if (flat.length) {
        spawnRows.push(`P[${id}]=${luaRow(flat)}`);
        withSpawns++;
      }
    }
  }

  const refRows = [];
  for (const id of [...usedObjects].sort((a, b) => a - b)) {
    const o = objects.get(id) ?? {};
    const zoneIdxs = [...new Set((o.zones ?? []).map(zoneIdxOfArea).filter(Boolean))];
    refRows.push(`O[${id}]=${luaRow([o.name ?? `Object ${id}`, ...zoneIdxs])}`);
  }
  for (const id of [...usedQuests].sort((a, b) => a - b)) {
    const q = quests.get(id) ?? {};
    refRows.push(`Q[${id}]=${luaRow([q.name ?? `Quest ${id}`, q.level])}`);
  }
  for (const id of [...usedSpells].sort((a, b) => a - b)) {
    const s = spells.get(id) ?? {};
    refRows.push(`X[${id}]=${luaRow([s.name ?? `Spell ${id}`, s.learnedAt])}`);
  }

  // zone index -> uiMapID, where the snapshot knows it
  const byName = new Map();
  for (const z of Object.values(zoneInfo)) if (z.name && z.uiMapId && !byName.has(z.name)) byName.set(z.name, z.uiMapId);
  const zoneMaps = zones.list.map((name) => byName.get(name));

  Object.assign(stats, { schema: 2, withSpawns, objects: usedObjects.size, quests: usedQuests.size, spells: usedSpells.size });
  return { snapshot: manifest.scrapedAt ?? manifest.date, npcRows, levelRows, tagRows, reactRows, spawnRows, refRows, zoneMaps };
}

// ---------- schema 1 (data/items.json) ----------
function convertSchema1() {
  const raw = JSON.parse(fs.readFileSync(path.join(dataDir, "items.json"), "utf8"));
  const npcs = new Map();
  for (const it of [...raw.items].sort((a, b) => a.id - b.id)) {
    let mask = 0;
    for (const part of (it.obtainedBy ?? "").split(/,\s*/)) mask |= SOURCE_BITS[part] ?? 0;
    const drops = it.droppedBy ?? [];
    const dropTotal = drops.length + (it.droppedByTruncated ?? 0);
    itemRows.push(
      `I[${it.id}]=` +
        luaRow([it.name, QUALITY[it.quality], int(it.itemLevel), int(it.requiredLevel), slots.idx(it.slot),
          mask || undefined, copper(it.sellPrice), zones.idx(it.zone), it.from, dropTotal || undefined])
    );
    if (drops.length) {
      const flat = [it.droppedByTruncated ?? 0];
      for (const d of drops) {
        flat.push(d.npcId, basisPointsFromText(d.dropChance) ?? -1, d.samples ?? 0, 100);
        let npc = npcs.get(d.npcId);
        if (!npc) npcs.set(d.npcId, (npc = { name: d.npcName, zones: new Set() }));
        for (const z of d.zones ?? []) npc.zones.add(zones.idx(z));
      }
      dropRows.push(`R[${it.id}]=${luaRow(flat)}`);
    }
  }
  const npcRows = [...npcs.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([id, n]) => `N[${id}]=${luaRow([n.name ?? `NPC ${id}`, ...n.zones])}`);
  return { snapshot: raw.scrapedAt, npcRows, levelRows: [], tagRows: [], reactRows: [], spawnRows: [], refRows: [], zoneMaps: [] };
}

const out = fs.existsSync(path.join(dataDir, "manifest.json")) ? convertSchema2() : convertSchema1();

// ---------- write ----------
const coreDir = path.join(outRoot, "HeadWow", "Data", "Generated");
const dropsDir = path.join(outRoot, "HeadWow_Drops", "Generated");
resetDir(coreDir);
resetDir(dropsDir);

const meta = [
  "-- Generated by tools/convert.mjs. Do not edit.",
  "local D = HeadWowData",
  `D.snapshot = ${luaStr(out.snapshot ?? "")}`,
  `D.zones = ${luaRow(zones.list)}`,
  `D.zoneMaps = ${"{" + out.zoneMaps.map((m, i) => (m ? `[${i + 1}]=${m}` : null)).filter(Boolean).join(",") + "}"}`,
  `D.slots = ${luaRow(slots.list)}`,
  `D.itemCount = ${itemRows.length}`,
  `D.npcCount = ${out.npcRows.length}`,
  "",
].join("\n");
fs.writeFileSync(path.join(coreDir, "Meta.lua"), meta);

const itemFiles = writeChunks(coreDir, "Items", "local I = HeadWowData.items", itemRows);
const npcFiles = writeChunks(coreDir, "Npcs", "local N = HeadWowData.npcs", out.npcRows);
const infoFiles = writeChunks(coreDir, "NpcInfo", "local L, T, F = HeadWowData.npcLevels, HeadWowData.npcTags, HeadWowData.npcReact",
  [...out.levelRows, ...out.tagRows, ...out.reactRows]);
writeXml(coreDir, ["Meta.lua", ...itemFiles, ...npcFiles, ...infoFiles]);

const dropFiles = writeChunks(dropsDir, "Drops", "local R = HeadWowData.drops", dropRows);
const sourceFiles = writeChunks(dropsDir, "Sources", "local S = HeadWowData.sources", sourceRows);
const spawnFiles = writeChunks(dropsDir, "Spawns", "local P = HeadWowData.spawns", out.spawnRows);
const refFiles = writeChunks(dropsDir, "Refs", "local O, Q, X = HeadWowData.objects, HeadWowData.quests, HeadWowData.spells", out.refRows);
writeXml(dropsDir, [...dropFiles, ...sourceFiles, ...spawnFiles, ...refFiles]);

const size = (dir, prefix) =>
  fs.readdirSync(dir).filter((f) => !prefix || f.startsWith(prefix)).reduce((s, f) => s + fs.statSync(path.join(dir, f)).size, 0);
const mb = (n) => (n / 1e6).toFixed(2) + " MB";
console.log(`snapshot  ${out.snapshot} (schema ${stats.schema})`);
console.log(`items     ${itemRows.length} rows; core addon ${mb(size(coreDir))}`);
console.log(`npcs      ${out.npcRows.length} (levels ${out.levelRows.length}, reactions ${out.reactRows.length}, spawns ${out.spawnRows.length})`);
console.log(`drops     ${dropRows.length} tables -> ${mb(size(dropsDir, "Drops"))} (${stats.droppedRowsLeftOut} rows under ${MIN_DROP_BP / 100}% left out)`);
console.log(`sources   ${sourceRows.length} items -> ${mb(size(dropsDir, "Sources"))}; spawns ${mb(size(dropsDir, "Spawns"))}; refs ${mb(size(dropsDir, "Refs"))}`);
console.log(`zones     ${zones.list.length} (${out.zoneMaps.filter(Boolean).length} with a map ID), slots ${slots.list.length}`);

if (statsPath) {
  fs.mkdirSync(path.dirname(path.resolve(statsPath)), { recursive: true });
  fs.writeFileSync(statsPath, JSON.stringify({
    snapshot: out.snapshot ?? null,
    schema: stats.schema,
    items: itemRows.length,
    npcs: out.npcRows.length,
    drops: dropRows.length,
    sources: sourceRows.length,
    spawns: out.spawnRows.length,
    zones: zones.list.length,
  }, null, 2) + "\n");
}
