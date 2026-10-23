// EverPlay machine translation for RPG Maker MV/MZ (only loaded when it is on for the game).
// Before a message window or a choice opens, its lines are translated by EverPlay
// (window.webkit.messageHandlers.everplayTranslate, which replies with the translations); the
// event waits up to a few seconds for them. Lines further down the same event are requested
// ahead. Translations replace the text only on its way into the message window.
(() => {
  'use strict';
  if (window.__everplayTranslation) return;

  const cache = new Map();
  const pending = new Set();
  const maxWait = 4000;
  const state = { original: false, installed: false };

  function native() {
    const handlers = window.webkit && window.webkit.messageHandlers;
    return handlers && handlers.everplayTranslate;
  }

  function request(lines) {
    const missing = [...new Set(lines)].filter((line) => typeof line === 'string' && line.trim() && !cache.has(line) && !pending.has(line));
    const bridge = native();
    if (!missing.length || !bridge) return;
    for (let start = 0; start < missing.length; start += 40) {
      const batch = missing.slice(start, start + 40);
      batch.forEach((line) => pending.add(line));
      Promise.resolve(bridge.postMessage(batch)).then((results) => {
        batch.forEach((line, i) => cache.set(line, (Array.isArray(results) && typeof results[i] === 'string' && results[i]) || line));
      }, () => {
        batch.forEach((line) => cache.set(line, line));
      }).finally(() => batch.forEach((line) => pending.delete(line)));
    }
  }

  const ready = (lines) => lines.every((line) => typeof line !== 'string' || !line.trim() || cache.has(line));
  const translated = (text) => (state.original || typeof text !== 'string' ? text : cache.get(text) || text);

  // Text shown by the event commands from `index` on: message lines (401), scrolling text (405),
  // choices (102) and MZ speaker names (101).
  function texts(list, index, limit) {
    const out = [];
    for (let i = index; list && i < list.length && out.length < limit; i++) {
      const command = list[i];
      if (!command) continue;
      const params = command.parameters || [];
      if (command.code === 401 || command.code === 405) out.push(params[0]);
      else if (command.code === 102 && Array.isArray(params[0])) out.push(...params[0]);
      else if (command.code === 101 && typeof params[4] === 'string') out.push(params[4]);
    }
    return out;
  }

  function following(list, index, code) {
    const out = [];
    for (let i = index + 1; list && list[i] && list[i].code === code; i++) out.push(list[i].parameters[0]);
    return out;
  }

  function install() {
    const Interpreter = window.Game_Interpreter;
    const Message = window.Game_Message;
    if (state.installed || !Interpreter || !Message || !window.$dataSystem) return state.installed;
    state.installed = true;
    const prototype = Interpreter.prototype;

    function waitFor(code, linesOf) {
      const original = prototype['command' + code];
      if (typeof original !== 'function') return;
      prototype['command' + code] = function (...args) {
        if (!state.original && native()) {
          const params = args[0] || this._params || [];
          const lines = linesOf(this, params);
          request(lines.concat(texts(this._list, this._index + 1, 60)));
          if (!ready(lines)) {
            if (!this._everplayWaitSince) this._everplayWaitSince = Date.now();
            if (Date.now() - this._everplayWaitSince < maxWait) return false; // run this command again next frame
          }
          this._everplayWaitSince = 0;
        }
        return original.apply(this, args);
      };
    }

    waitFor(101, (interpreter, params) => following(interpreter._list, interpreter._index, 401)
      .concat(typeof params[4] === 'string' ? [params[4]] : []));
    waitFor(102, (interpreter, params) => (Array.isArray(params[0]) ? params[0] : []));
    waitFor(105, (interpreter) => following(interpreter._list, interpreter._index, 405));

    const add = Message.prototype.add;
    Message.prototype.add = function (text) { return add.call(this, translated(text)); };
    const setChoices = Message.prototype.setChoices;
    Message.prototype.setChoices = function (choices, ...rest) {
      return setChoices.call(this, Array.isArray(choices) ? choices.map(translated) : choices, ...rest);
    };
    if (typeof Message.prototype.setSpeakerName === 'function') {
      const setSpeakerName = Message.prototype.setSpeakerName;
      Message.prototype.setSpeakerName = function (name) { return setSpeakerName.call(this, translated(name)); };
    }
    return true;
  }

  // MZ loads its scripts after the page; wait until the database (and so every plugin) is loaded.
  const timer = setInterval(() => { if (install()) clearInterval(timer); }, 250);
  install();

  window.__everplayTranslation = Object.freeze({
    install,
    setOriginal(on) { state.original = Boolean(on); return state.original; },
    status: () => ({ installed: state.installed, original: state.original, known: cache.size, pending: pending.size }),
  });
})();
