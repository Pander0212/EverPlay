// EverPlay's RPG Maker translation hook against a stand-in for the MV/MZ interpreter.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const source = readFileSync(new URL('../App/Resources/RPGMakerTranslate.js', import.meta.url), 'utf8');
const settle = () => new Promise((resolve) => setImmediate(resolve));

function engine() {
  const requests = [];
  class GameMessage {
    constructor() { this.lines = []; this.choices = []; this.speaker = ''; }
    add(text) { this.lines.push(text); }
    setChoices(choices) { this.choices = choices; }
    setSpeakerName(name) { this.speaker = name; }
  }
  const message = new GameMessage();
  class GameInterpreter {
    constructor(list) { this._list = list; this._index = 0; }
    command101(params) {
      message.setSpeakerName(params[4] || '');
      while (this._list[this._index + 1] && this._list[this._index + 1].code === 401) {
        this._index++;
        message.add(this._list[this._index].parameters[0]);
      }
      return true;
    }
    command102(params) { message.setChoices(params[0]); return true; }
  }
  const context = {
    Game_Interpreter: GameInterpreter,
    Game_Message: GameMessage,
    $dataSystem: {},
    setInterval: () => 1,
    clearInterval: () => {},
    webkit: { messageHandlers: { everplayTranslate: { postMessage: (lines) => {
      requests.push(lines);
      return Promise.resolve(lines.map((line) => 'DE:' + line));
    } } } },
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(source, context);
  return { context, message, requests, GameInterpreter };
}

test('a message waits for its translation, then shows it; later lines are requested ahead', async () => {
  const { context, message, requests, GameInterpreter } = engine();
  const list = [
    { code: 101, parameters: ['', 0, 0, 2, 'Anna'] },
    { code: 401, parameters: ['\\C[2]Hello\\C[0]!'] },
    { code: 401, parameters: ['How are you?'] },
    { code: 102, parameters: [['Fine', 'Bad']] },
    { code: 101, parameters: ['', 0, 0, 2, ''] },
    { code: 401, parameters: ['See you.'] },
  ];
  const interpreter = new GameInterpreter(list);
  assert.equal(interpreter.command101(list[0].parameters), false, 'waits while the lines are translated');
  assert.equal(message.lines.length, 0);
  assert.ok(requests.flat().includes('See you.'), 'requests what comes later in the event');
  await settle();
  assert.equal(interpreter.command101(list[0].parameters), true);
  assert.deepEqual([...message.lines], ['DE:\\C[2]Hello\\C[0]!', 'DE:How are you?']);
  assert.equal(message.speaker, 'DE:Anna');
  interpreter._index = 3;
  assert.equal(interpreter.command102(list[3].parameters), true, 'choices were translated ahead');
  assert.deepEqual([...message.choices], ['DE:Fine', 'DE:Bad']);
  assert.equal(context.__everplayTranslation.status().installed, true);
});

test('original text mode neither waits nor translates', () => {
  const { context, message, GameInterpreter } = engine();
  context.__everplayTranslation.setOriginal(true);
  const list = [{ code: 101, parameters: ['', 0, 0, 2] }, { code: 401, parameters: ['Hello'] }];
  assert.equal(new GameInterpreter(list).command101(list[0].parameters), true);
  assert.deepEqual([...message.lines], ['Hello']);
});

test('without EverPlay the game is not held up', () => {
  const { context, message, GameInterpreter } = engine();
  delete context.webkit;
  const list = [{ code: 101, parameters: ['', 0, 0, 2] }, { code: 401, parameters: ['Unanswered'] }];
  const interpreter = new GameInterpreter(list);
  assert.equal(interpreter.command101(list[0].parameters), true);
  assert.deepEqual([...message.lines], ['Unanswered']);
});
