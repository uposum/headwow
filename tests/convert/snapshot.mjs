// A tiny schema 2 snapshot (the scraper's format, see its src/snapshot.ts) for the converter test.
import fs from "node:fs";
import path from "node:path";

const jsonl = (records) => records.map((r) => JSON.stringify(r)).join("\n") + "\n";

export function writeSnapshot(root) {
  const dir = path.join(root, "data");
  fs.mkdirSync(dir, { recursive: true });

  // Item 1: 30 droppers, the first 24 from 10% down, the last 6 at 0.01%: the best 25 are kept,
  // the 5 under 0.05% beyond them are left out.
  const droppedBy = [];
  for (let i = 0; i < 30; i++) droppedBy.push([1001 + i, i < 24 ? 10 - i * 0.1 : 0.01, 500]);
  droppedBy[0].push(2); // 2 at a time

  fs.writeFileSync(path.join(dir, "manifest.json"), JSON.stringify({
    schema: 2,
    scrapedAt: "2026-11-18T05:00:00.000Z",
    files: {
      manifest: "manifest.json", items: "items.jsonl", pages: "item-pages.jsonl", npcs: "npcs.jsonl",
      objects: "objects.jsonl", quests: "quests.jsonl", spells: "spells.jsonl", zones: "zones.json",
    },
  }));
  fs.writeFileSync(path.join(dir, "items.jsonl"), jsonl([
    { id: 1, name: "Boar Tusk", origin: "listing", quality: "Poor", itemLevel: 5, obtainedBy: "Drop", zone: "Elwynn Forest", sellCopper: 105 },
    { id: 2, name: "Courser Eye", slug: "courser-eye", origin: "sitemap" },
    { id: 3, name: "Light Leather", origin: "listing", quality: "Common", itemLevel: 10, sellCopper: 15 },
    { id: 4, name: "Nothing Known", origin: "listing", quality: "Common" },
  ]));
  fs.writeFileSync(path.join(dir, "item-pages.jsonl"), jsonl([
    { id: 1, fetchedAt: "2026-11-18", droppedBy },
    { id: 2, fetchedAt: "2026-11-18", self: { name: "Courser Eye", quality: "Common", itemLevel: 22, reqLevel: 20, sellCopper: 7, slot: "Trinket" },
      droppedBy: [[4018, 85.5, 10000]] },
    { id: 3, fetchedAt: "2026-11-17", self: { buyCopper: 60 },
      soldBy: [[151, 25, -1, 5]], skinnedFrom: [[113, 71.7, 35000, 1.5]], minedFrom: [[1731, 96.6, 150000]],
      fishedIn: [[17, 0.00103, 290000, 3.33]], containedInItem: [[6307, 0.0835, 1200]], rewardFrom: [8], createdBy: [2881] },
    { id: 4, fetchedAt: "2026-11-10", missing: true },
  ]));
  fs.writeFileSync(path.join(dir, "npcs.jsonl"), jsonl([
    { id: 113, name: "Stonetusk Boar", minLevel: 5, maxLevel: 6, classification: 0, zones: [12], spawns: { 1429: [[46.9, 35.7], [47.4, 100]] } },
    { id: 151, name: "Brog Hamfist", tag: "General Supplies", minLevel: 10, maxLevel: 10, zones: [12] },
    { id: 4018, name: "Big Boss", classification: 3, zones: [17] },
  ]));
  fs.writeFileSync(path.join(dir, "objects.jsonl"), jsonl([{ id: 1731, name: "Copper Vein", type: -4, zones: [17] }]));
  fs.writeFileSync(path.join(dir, "quests.jsonl"), jsonl([{ id: 8, name: "A Rogue's Deal", level: 5 }]));
  fs.writeFileSync(path.join(dir, "spells.jsonl"), jsonl([{ id: 2881, name: "Light Leather", learnedAt: 20 }]));
  fs.writeFileSync(path.join(dir, "zones.json"), JSON.stringify({ 12: { name: "Elwynn Forest", uiMapId: 1429 }, 17: { name: "The Barrens" } }));
}
