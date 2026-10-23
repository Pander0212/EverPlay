// EverPlay: harmless stand-ins for the Node.js/NW.js APIs that RPG Maker MV/MZ plugins written for
// the desktop player call (require('fs'), require('path'), nw.Window, ...). They let such plugins
// load instead of stopping the game. `process` stays undefined on purpose: the engine's
// Utils.isNwjs() then remains false and saves keep using the browser storage EverPlay manages.
(() => {
  'use strict';
  if (typeof window.require === 'function') return;
  const noop = () => {};
  const missing = (name) => Object.assign(new Error('ENOENT: no such file, ' + name), { code: 'ENOENT' });
  const callback = (...args) => args.reverse().find((value) => typeof value === 'function');

  const path = {
    sep: '/',
    delimiter: ':',
    join: (...parts) => parts.filter((part) => part !== '').join('/').replace(/\/+/g, '/') || '.',
    resolve: (...parts) => path.join(...parts),
    normalize: (value) => String(value).replace(/\/+/g, '/'),
    dirname: (value) => String(value).replace(/\/[^/]*$/, '') || '.',
    basename: (value, extension) => {
      const base = String(value).split('/').pop();
      return extension && base.endsWith(extension) ? base.slice(0, -extension.length) : base;
    },
    extname: (value) => (/\.[^./]*$/.exec(String(value)) || [''])[0],
    relative: (from, to) => String(to),
    isAbsolute: (value) => String(value).startsWith('/'),
  };

  const fs = {
    existsSync: () => false,
    readFileSync: (name) => { throw missing(name); },
    statSync: (name) => { throw missing(name); },
    lstatSync: (name) => { throw missing(name); },
    readdirSync: () => [],
    writeFileSync: noop,
    appendFileSync: noop,
    mkdirSync: noop,
    unlinkSync: noop,
    renameSync: noop,
    copyFileSync: noop,
    exists: (name, done) => done && done(false),
    readFile: (name, ...rest) => { const done = callback(...rest); if (done) done(missing(name)); },
    writeFile: (name, data, ...rest) => { const done = callback(...rest); if (done) done(null); },
    readdir: (name, ...rest) => { const done = callback(...rest); if (done) done(null, []); },
    mkdir: (name, ...rest) => { const done = callback(...rest); if (done) done(null); },
    unlink: (name, done) => done && done(null),
  };

  const windowStub = {
    on: noop, once: noop, removeListener: noop, removeAllListeners: noop, close: noop, show: noop, hide: noop,
    focus: noop, blur: noop, maximize: noop, minimize: noop, restore: noop, enterFullscreen: noop,
    leaveFullscreen: noop, toggleFullscreen: noop, setResizable: noop, resizeTo: noop, resizeBy: noop,
    moveTo: noop, moveBy: noop, setPosition: noop, showDevTools: noop, closeDevTools: noop, reload: noop,
    isFullscreen: false, isDevToolsOpen: () => false, title: document.title, width: window.innerWidth,
    height: window.innerHeight, x: 0, y: 0, zoomLevel: 0,
  };
  function Menu() { return { append: noop, insert: noop, remove: noop, popup: noop, createMacBuiltin: noop, items: [] }; }
  function MenuItem(options) { return Object.assign({}, options); }
  const gui = {
    Window: { get: () => windowStub, open: () => windowStub },
    App: { quit: noop, closeAllWindows: noop, argv: [], fullArgv: [], dataPath: '', manifest: {}, clearCache: noop },
    Shell: { openExternal: noop, openItem: noop, showItemInFolder: noop },
    Screen: { Init: noop, screens: [], on: noop },
    Clipboard: { get: () => ({ get: () => '', set: noop, clear: noop }) },
    Menu,
    MenuItem,
  };
  function EventEmitter() {}
  EventEmitter.prototype.on = EventEmitter.prototype.once = EventEmitter.prototype.emit = noop;

  const modules = {
    fs,
    path,
    os: { platform: () => 'ios', type: () => 'Darwin', release: () => '', homedir: () => '/', tmpdir: () => '/tmp', EOL: '\n', cpus: () => [] },
    'nw.gui': gui,
    child_process: { exec: (command, ...rest) => { const done = callback(...rest); if (done) done(new Error('not available on iOS')); }, execSync: () => '', spawn: () => ({ on: noop, stdout: { on: noop }, stderr: { on: noop } }) },
    events: EventEmitter,
    util: { inherits: (child, parent) => Object.setPrototypeOf(child.prototype, parent.prototype), format: (...args) => args.join(' ') },
    crypto: {},
    zlib: {},
  };

  window.require = function require(name) {
    const key = String(name).replace(/^node:/, '');
    if (Object.prototype.hasOwnProperty.call(modules, key)) return modules[key];
    console.warn('EverPlay: require(' + JSON.stringify(key) + ') is not available on iOS');
    return {};
  };
  if (!window.nw) window.nw = { Window: gui.Window, App: gui.App, Shell: gui.Shell, Screen: gui.Screen, Menu, MenuItem };
})();
