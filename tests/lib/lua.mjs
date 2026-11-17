// A fresh Lua state (fengari, Lua 5.3 in JS) to run addon files in.
import fs from "node:fs";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring } = fengari;

export function newLua() {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = (code, name) => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring("@" + name)) !== 0 || lua.lua_pcall(L, 0, 0, 0) !== 0) {
      const err = lua.lua_tojsstring(L, -1);
      lua.lua_pop(L, 1);
      throw new Error(`${name}: ${err}`);
    }
  };
  const runFile = (file, name = file, patch = (code) => code) => run(patch(fs.readFileSync(file, "utf8")), name);
  return { run, runFile };
}

// Core.lua takes its addon name from the file's varargs, as the game passes it.
export const coreName = (code) => code.replace("local ADDON_NAME = ...", 'local ADDON_NAME = "HeadWow"');
