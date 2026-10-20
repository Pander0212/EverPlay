import { SAVE_KEY, freshState, restoreState, act } from './state.js';

const element = id => document.getElementById(id);
let state = freshState();
let storageAvailable = true;
let saveBlocked = false;
let sound = false;
let audio;
try { state = restoreState(localStorage.getItem(SAVE_KEY)); }
catch {
  // Do not silently replace an unknown or damaged save.
  saveBlocked = true;
  element('saveStatus').textContent = 'Existing save unreadable; automatic saving disabled';
}

function save() {
  if (saveBlocked) return;
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(state)); element('saveStatus').textContent = 'Saved on this device'; }
  catch { storageAvailable = false; element('saveStatus').textContent = 'Storage unavailable — progress is temporary'; }
}
function chime() {
  if (!sound) return;
  audio ??= new AudioContext();
  audio.resume().catch(() => {});
  const oscillator = audio.createOscillator();
  const gain = audio.createGain();
  oscillator.frequency.value = 660;
  gain.gain.setValueAtTime(0.08, audio.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + 0.22);
  oscillator.connect(gain).connect(audio.destination);
  oscillator.start(); oscillator.stop(audio.currentTime + 0.23);
}
let dialogue = [];
function render() {
  element('gold').value = state.gold;
  element('day').value = state.day;
  element('inventory').textContent = `Seeds: ${state.seeds}`;
  element('player').style.left = `${state.x}%`;
  element('dialogue').textContent = dialogue[state.dialogue % dialogue.length]?.text ?? '…';
  element('seed').disabled = state.gold < 20;
}
function perform(action) { state = act(state, action); render(); save(); if (action === 'collect') chime(); }
for (const [id, action] of Object.entries({ collect: 'collect', lantern: 'collect', seed: 'seed', nextDay: 'day', talk: 'talk' })) {
  element(id).addEventListener('click', () => perform(action));
}
element('save').addEventListener('click', save);
element('sound').addEventListener('click', () => {
  sound = !sound; element('sound').textContent = sound ? 'Sound on' : 'Sound off';
  element('sound').setAttribute('aria-pressed', String(sound)); chime();
});
document.addEventListener('keydown', event => {
  const action = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'collect', Enter: 'talk', z: 'collect', x: 'talk' }[event.key];
  if (action && !event.repeat) { event.preventDefault(); perform(action); }
});
window.addEventListener('pagehide', save);
document.addEventListener('visibilitychange', () => { if (document.hidden) save(); });
try {
  const response = await fetch('./dialogue.json');
  if (!response.ok) throw new Error('Dialogue unavailable');
  dialogue = await response.json();
  render();
  if (!saveBlocked && storageAvailable) element('saveStatus').textContent = 'Ready · progress saves automatically';
  document.body.dataset.ready = 'true';
} catch { element('saveStatus').textContent = 'Could not load game resources'; }
