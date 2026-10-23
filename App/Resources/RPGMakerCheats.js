// EverPlay cheats for RPG Maker MV and MZ games, loaded into the game page by EverPlay.
// The native cheat screen calls window.__everplayCheats.<method>(...) with JSON-encoded
// arguments and reads the JSON it returns. Game data is only read and changed through the
// engine's own objects ($gameParty, $gameVariables, ...), the same way an event command would.
(() => {
  'use strict';
  if (window.__everplayCheats) return;

  const state = { speed: 1, through: false, noEncounters: false, patched: false };
  const limit = 400;

  const defined = (value) => typeof value !== 'undefined' && value !== null;
  const ready = () => defined(window.$gameParty) && defined(window.$dataSystem) &&
    defined(window.$gameVariables) && defined(window.$gameSwitches);
  const engine = () => (defined(window.Utils) && window.Utils.RPGMAKER_NAME) || null;

  // Wraps the engine at first use, after the game's plugins have changed what they change.
  function patch() {
    if (state.patched || !defined(window.SceneManager) || !defined(window.Game_Player)) return;
    state.patched = true;
    const manager = window.SceneManager;
    const updateScene = manager.updateScene;
    manager.updateScene = function () {
      updateScene.call(this);
      // Extra steps read input again, so one tap does not count several times.
      for (let i = 1; i < state.speed; i++) {
        if (this.updateInputData) this.updateInputData();
        updateScene.call(this);
      }
    };
    const player = window.Game_Player.prototype;
    const isDebugThrough = player.isDebugThrough;
    player.isDebugThrough = function () {
      return state.through || (isDebugThrough ? isDebugThrough.call(this) : false);
    };
    const canEncounter = player.canEncounter;
    player.canEncounter = function () {
      return !state.noEncounters && (canEncounter ? canEncounter.call(this) : true);
    };
  }

  function plain(value) {
    if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'string') return value;
    try {
      return JSON.stringify(value).slice(0, 80);
    } catch (error) {
      return String(value).slice(0, 80);
    }
  }

  // "abc" searches names, "#12" an id, "=5" a value.
  function matches(query, id, name, value) {
    const q = String(query || '').trim().toLowerCase();
    if (!q) return true;
    if (q.startsWith('#')) return String(id) === q.slice(1).trim();
    if (q.startsWith('=')) return String(value).toLowerCase() === q.slice(1).trim();
    return String(name || '').toLowerCase().includes(q);
  }

  function status() {
    if (!ready()) return { engine: engine(), ready: false };
    patch();
    const party = window.$gameParty;
    return {
      engine: engine(),
      ready: true,
      gold: party.gold(),
      maxGold: party.maxGold(),
      party: party.members().map((actor) => ({
        id: actor.actorId(), name: actor.name(), level: actor.level,
        hp: actor.hp, mhp: actor.mhp, mp: actor.mp, mmp: actor.mmp,
      })),
      speed: state.speed,
      through: state.through,
      noEncounters: state.noEncounters,
    };
  }

  function number(value) {
    const result = Number(value);
    if (!Number.isFinite(result)) throw new Error('not a number');
    return result;
  }

  function dataFor(kind) {
    const data = { item: window.$dataItems, weapon: window.$dataWeapons, armor: window.$dataArmors }[kind];
    if (!data) throw new Error('unknown item kind');
    return data;
  }

  window.__everplayCheats = Object.freeze({
    version: 1,
    status,
    addGold(amount) {
      window.$gameParty.gainGold(Math.trunc(number(amount)));
      return status();
    },
    setGold(amount) {
      const party = window.$gameParty;
      party.gainGold(Math.trunc(number(amount)) - party.gold());
      return status();
    },
    heal() {
      window.$gameParty.members().forEach((actor) => actor.recoverAll());
      return status();
    },
    levelUp(levels) {
      const step = Math.trunc(number(levels));
      window.$gameParty.members().forEach((actor) => {
        actor.changeLevel(Math.max(1, Math.min(actor.maxLevel(), actor.level + step)), false);
      });
      return status();
    },
    setSpeed(speed) {
      patch();
      state.speed = Math.max(1, Math.min(8, Math.trunc(number(speed))));
      return status();
    },
    setThrough(on) {
      patch();
      state.through = Boolean(on);
      return status();
    },
    setNoEncounters(on) {
      patch();
      state.noEncounters = Boolean(on);
      return status();
    },
    variables(query) {
      const names = window.$dataSystem.variables || [];
      const out = [];
      for (let id = 1; id < names.length && out.length < limit; id++) {
        const name = names[id] || '';
        const value = window.$gameVariables.value(id);
        if (!name && !value) continue;
        if (!matches(query, id, name, plain(value))) continue;
        out.push({ id, name, value: plain(value), number: typeof value === 'number' });
      }
      return out;
    },
    setVariable(id, value) {
      window.$gameVariables.setValue(Math.trunc(number(id)), number(value));
      return true;
    },
    switches(query) {
      const names = window.$dataSystem.switches || [];
      const out = [];
      for (let id = 1; id < names.length && out.length < limit; id++) {
        const name = names[id] || '';
        const value = window.$gameSwitches.value(id);
        if (!name && !value) continue;
        if (!matches(query, id, name, value)) continue;
        out.push({ id, name, value: Boolean(value) });
      }
      return out;
    },
    setSwitch(id, on) {
      window.$gameSwitches.setValue(Math.trunc(number(id)), Boolean(on));
      return true;
    },
    items(kind, query) {
      const data = dataFor(kind);
      const party = window.$gameParty;
      const out = [];
      for (let id = 1; id < data.length && out.length < limit; id++) {
        const entry = data[id];
        if (!entry || !entry.name) continue;
        const count = party.numItems(entry);
        if (!matches(query, id, entry.name, count)) continue;
        out.push({ id, name: entry.name, count, max: party.maxItems(entry) });
      }
      return out;
    },
    gainItem(kind, id, amount) {
      const entry = dataFor(kind)[Math.trunc(number(id))];
      if (!entry) throw new Error('unknown item');
      window.$gameParty.gainItem(entry, Math.trunc(number(amount)), false);
      return true;
    },
  });
})();
