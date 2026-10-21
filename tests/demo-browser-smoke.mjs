import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const site = 'http://127.0.0.1:4173';
const chromePath = process.env.CHROME_BIN ?? 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const delay = (ms) => new Promise((done) => setTimeout(done, ms));

async function eventually(callback, description) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const value = await callback();
      if (value) return value;
    } catch { /* The browser/server may still be starting. */ }
    await delay(100);
  }
  throw new Error(`Timed out: ${description}`);
}

class DevTools {
  constructor(url) {
    this.socket = new WebSocket(url);
    this.nextId = 0;
    this.pending = new Map();
    this.exceptions = [];
    this.socket.addEventListener('message', (event) => {
      const message = JSON.parse(event.data);
      if (message.method === 'Runtime.exceptionThrown') {
        this.exceptions.push(message.params.exceptionDetails.text);
      }
      if (!message.id) return;
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(JSON.stringify(message.error)));
      else pending.resolve(message.result);
    });
  }

  async ready() {
    await new Promise((resolveReady, reject) => {
      this.socket.addEventListener('open', resolveReady, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
    await this.call('Page.enable');
    await this.call('Runtime.enable');
  }

  call(method, params = {}) {
    const id = ++this.nextId;
    return new Promise((resolveCall, reject) => {
      this.pending.set(id, { resolve: resolveCall, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const result = await this.call('Runtime.evaluate', {
      expression, awaitPromise: true, returnByValue: true,
    });
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text);
    return result.result.value;
  }

  close() { this.socket.close(); }
}

const server = spawn(process.execPath, ['demo/serve.mjs'], { cwd: root, stdio: 'ignore' });
let chrome;
let devtools;
let profile;
try {
  await eventually(async () => (await fetch(site)).ok, 'demo server');
  assert.ok(existsSync(chromePath), `Chrome not found: ${chromePath}`);
  profile = mkdtempSync(join(tmpdir(), 'deadlineplan-browser-'));
  chrome = spawn(chromePath, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, '--window-size=1440,1200',
    'about:blank',
  ], { stdio: 'ignore' });
  const port = await eventually(() => {
    const file = join(profile, 'DevToolsActivePort');
    return existsSync(file) ? readFileSync(file, 'utf8').split('\n')[0] : null;
  }, 'Chrome DevTools port');
  const targets = await eventually(async () => {
    const response = await fetch(`http://127.0.0.1:${port}/json`);
    const pages = await response.json();
    return pages.find((page) => page.type === 'page')?.webSocketDebuggerUrl;
  }, 'Chrome page target');
  devtools = new DevTools(targets);
  await devtools.ready();
  await devtools.call('Page.navigate', { url: site });
  await eventually(() => devtools.evaluate('window.__deadlineplanDemo?.getState().result?.ok'), 'student render');

  const student = await devtools.evaluate(`(() => {
    const state = window.__deadlineplanDemo.getState();
    return {
      scenario: state.scenario,
      blocks: state.result.blocks.length,
      confirmed: state.result.blocks.filter((block) => block.confirmed).length,
      exam: document.querySelector('[data-item-id="biology-exam"]')?.textContent,
      room: document.querySelector('[data-item-id="morning-lecture"]')?.textContent,
    };
  })()`);
  assert.equal(student.scenario, 'student');
  assert.equal(student.blocks, 5);
  assert.equal(student.confirmed, 1);
  assert.match(student.exam, /生物学期中考试/);
  assert.match(student.room, /理科楼 A203/);
  const screenshot = await devtools.call('Page.captureScreenshot', { format: 'png', captureBeyondViewport: true });
  writeFileSync(join(root, 'demo', 'screenshot.png'), Buffer.from(screenshot.data, 'base64'));
  console.log('student: 5 blocks, 1 confirmed, classroom/exam visible; screenshot saved');

  const edited = await devtools.evaluate(`(() => {
    const input = document.querySelector('.duration-input[data-task-index="1"]');
    input.value = '180';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    const state = window.__deadlineplanDemo.getState();
    return { reason: state.result.unscheduled.find((item) => item.task_id === 'calculus-homework')?.reason.code,
      confirmed: state.result.blocks.find((block) => block.confirmed)?.start };
  })()`);
  assert.equal(edited.reason, 'NoContinuousSlot');
  assert.equal(edited.confirmed, 29875680);
  console.log('task edit: 180-minute homework -> NoContinuousSlot; confirmed block unchanged');

  const conflict = await devtools.evaluate(`(() => {
    const start = window.__deadlineplanDemo.getState().plan.confirmed_blocks[0].start + 15;
    const fmt = (minute) => {
      const d = new Date(minute * 60000);
      const p = (n) => String(n).padStart(2, '0');
      return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
    };
    document.querySelector('#event-name').value = '临时讨论';
    document.querySelector('#event-start').value = fmt(start);
    document.querySelector('#event-end').value = fmt(start + 20);
    document.querySelector('#event-form').requestSubmit();
    return { error: window.__deadlineplanDemo.getState().result.error.message,
      banner: document.querySelector('#validation-banner').textContent,
      confirmed: window.__deadlineplanDemo.getState().plan.confirmed_blocks[0].start };
  })()`);
  assert.match(conflict.error, /ConfirmedOverlapsFixedEvent/);
  assert.match(conflict.banner, /ConfirmedOverlapsFixedEvent/);
  assert.equal(conflict.confirmed, 29875680);
  console.log('temporary event conflict: MoonBit returns ConfirmedOverlapsFixedEvent; confirmed block unchanged');

  const repaired = await devtools.evaluate(`(() => {
    document.querySelector('.remove-event').click();
    return window.__deadlineplanDemo.getState().result.ok;
  })()`);
  assert.equal(repaired, true);
  const newEvent = await devtools.evaluate(`(() => {
    const input = document.querySelector('.duration-input[data-task-index="1"]');
    input.value = '60';
    input.dispatchEvent(new Event('input', { bubbles: true }));
    const first = window.__deadlineplanDemo.getState().plan.availability[0].start;
    const fmt = (minute) => {
      const d = new Date(minute * 60000);
      const p = (n) => String(n).padStart(2, '0');
      return d.getFullYear() + '-' + p(d.getMonth() + 1) + '-' + p(d.getDate()) + 'T' + p(d.getHours()) + ':' + p(d.getMinutes());
    };
    document.querySelector('#event-name').value = '临时讨论';
    document.querySelector('#event-start').value = fmt(first + 150);
    document.querySelector('#event-end').value = fmt(first + 270);
    document.querySelector('#event-form').requestSubmit();
    const state = window.__deadlineplanDemo.getState();
    return { ok: state.result.ok,
      reason: state.result.unscheduled.find((item) => item.task_id === 'calculus-homework')?.reason.code,
      confirmed: state.result.blocks.find((block) => block.confirmed)?.start };
  })()`);
  assert.equal(newEvent.ok, true);
  assert.equal(newEvent.reason, 'NoContinuousSlot');
  assert.equal(newEvent.confirmed, 29875680);
  console.log('new fixed event: immediate replan reports NoContinuousSlot; confirmed block unchanged');
  await devtools.evaluate(`document.querySelector('.remove-event').click()`);
  await devtools.evaluate(`document.querySelector('[data-scenario="project"]').click()`);
  await eventually(() => devtools.evaluate('window.__deadlineplanDemo.getState().scenario === "project" && window.__deadlineplanDemo.getState().result?.ok'), 'project render');
  const project = await devtools.evaluate(`(() => {
    const state = window.__deadlineplanDemo.getState();
    return { blocks: state.result.blocks, vendor: document.querySelector('[data-item-id="vendor-call"]')?.textContent };
  })()`);
  assert.equal(project.blocks.length, 3);
  assert.deepEqual(project.blocks.find((block) => block.task_id === 'release'), {
    task_id: 'release', start: 29877220, end: 29877230, confirmed: false,
  });
  assert.match(project.vendor, /2026/);
  console.log('project: 3 blocks, release at 2026-10-22 UTC; same interface rendered');
  assert.deepEqual(devtools.exceptions, []);
  console.log('browser smoke: PASS');
} finally {
  devtools?.close();
  chrome?.kill();
  server.kill();
  if (profile && resolve(profile).startsWith(resolve(tmpdir()) + sep)) {
    try { rmSync(profile, { recursive: true, force: true }); } catch { /* Chrome may still be closing. */ }
  }
}
