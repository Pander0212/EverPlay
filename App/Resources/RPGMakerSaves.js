// EverPlay save editor for RPG Maker MV and MZ games, loaded into the game page by EverPlay.
// It edits a save slot without loading it: the slot is read and written with the engine's own
// StorageManager and JsonEx, exactly as the game's save and load commands do. The native save
// editor calls window.__everplaySaves.<method>(...) and awaits the JSON-ready result.
(() => {
  'use strict';
  if (window.__everplaySaves) return;

  const limit = 400;
  const defined = (value) => typeof value !== 'undefined' && value !== null;
  const isMZ = () => defined(window.Utils) && window.Utils.RPGMAKER_NAME === 'MZ';

  function number(value) {
    const result = Number(value);
    if (!Number.isFinite(result)) throw new Error('not a number');
    return result;
  }

  function slotId(value) {
    const id = Math.trunc(number(value));
    if (id < 0 || id > window.DataManager.maxSavefiles()) throw new Error('no such save slot');
    return id;
  }

  // MV numbers its slots from 1; MZ from 0, where 0 is the autosave.
  function slotIds() {
    const max = window.DataManager.maxSavefiles();
    const ids = [];
    for (let id = isMZ() ? 0 : 1; id <= (isMZ() ? max - 1 : max); id++) ids.push(id);
    return ids;
  }

  function info(id) {
    const manager = window.DataManager;
    if (isMZ()) return manager.savefileInfo ? manager.savefileInfo(id) : null;
    if (!window.StorageManager.exists(id)) return null;
    return (manager.loadSavefileInfo && manager.loadSavefileInfo(id)) || {};
  }

  async function load(id) {
    let contents;
    if (isMZ()) {
      contents = await window.StorageManager.loadObject(window.DataManager.makeSavename(id));
    } else {
      const json = window.StorageManager.load(id);
      if (!json) throw new Error('this save slot is empty');
      contents = window.JsonEx.parse(json);
    }
    if (!contents || !contents.party || !contents.variables) throw new Error('unreadable save (changed by a plugin?)');
    return contents;
  }

  async function store(id, contents) {
    if (isMZ()) {
      await window.StorageManager.saveObject(window.DataManager.makeSavename(id), contents);
    } else {
      // The engine's own backup first, which it restores when a save goes wrong.
      if (window.StorageManager.backup) window.StorageManager.backup(id);
      window.StorageManager.save(id, window.JsonEx.stringify(contents));
    }
  }

  async function change(id, edit) {
    const slot = slotId(id);
    const contents = await load(slot);
    edit(contents);
    await store(slot, contents);
    return summary(slot, contents);
  }

  function plain(value) {
    if (typeof value === 'number' || typeof value === 'boolean' || typeof value === 'string') return value;
    try {
      return JSON.stringify(value).slice(0, 80);
    } catch (error) {
      return String(value).slice(0, 80);
    }
  }

  // "abc" searches names, "#12" an id, "=5" a value (as in the cheat screen).
  function matches(query, id, name, value) {
    const q = String(query || '').trim().toLowerCase();
    if (!q) return true;
    if (q.startsWith('#')) return String(id) === q.slice(1).trim();
    if (q.startsWith('=')) return String(value).toLowerCase() === q.slice(1).trim();
    return String(name || '').toLowerCase().includes(q);
  }

  function dataFor(kind) {
    const data = { item: window.$dataItems, weapon: window.$dataWeapons, armor: window.$dataArmors }[kind];
    if (!data) throw new Error('unknown item kind');
    return data;
  }

  function bagFor(party, kind) {
    const key = { item: '_items', weapon: '_weapons', armor: '_armors' }[kind];
    if (!party[key]) party[key] = {};
    return party[key];
  }

  function maxItems(party, entry) {
    try {
      return party.maxItems(entry);
    } catch (error) {
      return 99;
    }
  }

  function actorsOf(contents) {
    const party = contents.party;
    const actors = (contents.actors && contents.actors._data) || [];
    return (party._actors || []).map((id) => actors[id]).filter(defined);
  }

  function summary(id, contents) {
    const party = contents.party;
    let maxGold = 99999999;
    try { maxGold = party.maxGold(); } catch (error) { /* plugin-changed party */ }
    return {
      id,
      gold: party._gold || 0,
      maxGold,
      actors: actorsOf(contents).map((actor, index) => {
        let maxLevel = 99;
        try { maxLevel = actor.maxLevel(); } catch (error) { /* missing class data */ }
        return { index, id: actor._actorId, name: actor._name || '', level: actor._level || 1, maxLevel };
      }),
    };
  }

  window.__everplaySaves = Object.freeze({
    version: 1,
    async slots() {
      if (!defined(window.DataManager) || !defined(window.StorageManager) || !defined(window.$dataSystem)) return [];
      return slotIds().map((id) => {
        const entry = info(id);
        if (!entry) return null;
        return { id, title: String(entry.title || ''), playtime: String(entry.playtime || ''),
                 timestamp: Number(entry.timestamp) || 0, autosave: isMZ() && id === 0 };
      }).filter(defined);
    },
    async summary(id) {
      const slot = slotId(id);
      return summary(slot, await load(slot));
    },
    async setGold(id, amount) {
      return change(id, (contents) => {
        const party = contents.party;
        let max = 99999999;
        try { max = party.maxGold(); } catch (error) { /* plugin-changed party */ }
        party._gold = Math.max(0, Math.min(max, Math.trunc(number(amount))));
      });
    },
    async setLevel(id, index, level) {
      return change(id, (contents) => {
        const actor = actorsOf(contents)[Math.trunc(number(index))];
        if (!actor) throw new Error('no such party member');
        let max = 99;
        try { max = actor.maxLevel(); } catch (error) { /* missing class data */ }
        const target = Math.max(1, Math.min(max, Math.trunc(number(level))));
        actor._level = target;
        // Experience to match, so the next battle does not level the actor back.
        try {
          if (!actor._exp) actor._exp = {};
          actor._exp[actor._classId] = actor.expForLevel(target);
        } catch (error) { /* plugin-changed experience */ }
        try { actor._hp = actor.mhp; actor._mp = actor.mmp; } catch (error) { /* keeps the old values */ }
      });
    },
    async variables(id, query) {
      const contents = await load(slotId(id));
      const names = window.$dataSystem.variables || [];
      const data = contents.variables._data || [];
      const out = [];
      for (let index = 1; index < Math.max(names.length, data.length) && out.length < limit; index++) {
        const name = names[index] || '';
        const value = defined(data[index]) ? data[index] : 0;
        if (!name && !value) continue;
        if (!matches(query, index, name, plain(value))) continue;
        out.push({ id: index, name, value: plain(value), number: typeof value === 'number' });
      }
      return out;
    },
    async setVariable(id, variable, value) {
      await change(id, (contents) => {
        if (!contents.variables._data) contents.variables._data = [];
        contents.variables._data[Math.trunc(number(variable))] = number(value);
      });
      return true;
    },
    async switches(id, query) {
      const contents = await load(slotId(id));
      const names = window.$dataSystem.switches || [];
      const data = contents.switches._data || [];
      const out = [];
      for (let index = 1; index < Math.max(names.length, data.length) && out.length < limit; index++) {
        const name = names[index] || '';
        const value = Boolean(data[index]);
        if (!name && !value) continue;
        if (!matches(query, index, name, value)) continue;
        out.push({ id: index, name, value });
      }
      return out;
    },
    async setSwitch(id, entry, on) {
      await change(id, (contents) => {
        if (!contents.switches._data) contents.switches._data = [];
        contents.switches._data[Math.trunc(number(entry))] = Boolean(on);
      });
      return true;
    },
    async items(id, kind, query) {
      const contents = await load(slotId(id));
      const data = dataFor(kind);
      const bag = bagFor(contents.party, kind);
      const out = [];
      for (let index = 1; index < data.length && out.length < limit; index++) {
        const entry = data[index];
        if (!entry || !entry.name) continue;
        const count = bag[index] || 0;
        if (!matches(query, index, entry.name, count)) continue;
        out.push({ id: index, name: entry.name, count, max: maxItems(contents.party, entry) });
      }
      return out;
    },
    async gainItem(id, kind, item, amount) {
      await change(id, (contents) => {
        const index = Math.trunc(number(item));
        const entry = dataFor(kind)[index];
        if (!entry) throw new Error('unknown item');
        const bag = bagFor(contents.party, kind);
        const count = Math.max(0, Math.min(maxItems(contents.party, entry), (bag[index] || 0) + Math.trunc(number(amount))));
        if (count > 0) bag[index] = count;
        else delete bag[index];
      });
      return true;
    },
  });
})();
