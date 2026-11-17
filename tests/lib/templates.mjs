// Turns HeadWow's XML templates into a Lua table for the mock client:
//   HW_TEMPLATES[name] = { kind, mixin, inherits, children = { { kind, parentKey, inherits, hidden } },
//                          scripts = { OnLoad = "OnLoad", ... }, keyValues = { ... } }
import fs from "node:fs";
import { XMLParser } from "fast-xml-parser";

const FRAME_KINDS = new Set(["Frame", "Button", "CheckButton", "EditBox", "ScrollFrame", "StatusBar", "Slider", "GameTooltip", "PlayerModel", "Model"]);
const REGION_KINDS = new Set(["Texture", "FontString", "MaskTexture"]);

const attrs = (node) => node[":@"] || {};
const tagOf = (node) => Object.keys(node).find((k) => k !== ":@");

function collect(nodes, tpl, isTop) {
  for (const node of nodes) {
    const tag = tagOf(node);
    if (!tag) continue;
    const a = attrs(node);
    if (REGION_KINDS.has(tag) || (FRAME_KINDS.has(tag) && !isTop)) {
      if (a.parentKey) tpl.children.push({ kind: tag, parentKey: a.parentKey, inherits: a.inherits ?? null, hidden: a.hidden === "true" });
      if (FRAME_KINDS.has(tag)) continue;
    }
    if (tag === "Scripts") {
      for (const s of node[tag]) {
        const st = tagOf(s);
        if (st) tpl.scripts[st] = attrs(s).method || "inline";
      }
      continue;
    }
    if (tag === "KeyValues") {
      for (const kv of node[tag]) {
        const k = attrs(kv);
        if (k.key) tpl.keyValues[k.key] = k.type === "number" ? Number(k.value) : k.value;
      }
      continue;
    }
    if (Array.isArray(node[tag])) collect(node[tag], tpl, false);
  }
}

function toLua(v) {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (Array.isArray(v)) return "{" + v.map(toLua).join(",") + "}";
  return "{" + Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${toLua(x)}`).join(",") + "}";
}

export function templatesLua(xmlFile) {
  const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "", preserveOrder: true });
  const out = {};
  for (const top of parser.parse(fs.readFileSync(xmlFile, "utf8"))) {
    for (const node of top.Ui ?? []) {
      const tag = tagOf(node);
      if (!tag || !FRAME_KINDS.has(tag)) continue;
      const a = attrs(node);
      const tpl = { kind: tag, mixin: a.mixin ?? null, inherits: a.inherits ?? null, children: [], scripts: {}, keyValues: {} };
      collect(node[tag], tpl, true);
      out[a.name] = tpl;
    }
  }
  return `HW_TEMPLATES = ${toLua(out)}\n`;
}
