// Presses → from the first slide to the last step of the last slide. Each step must show on screen (its line is the
// one marked now, at least one node is lit), every node a step or a link names must exist on its stage, every hop of a
// step's path must be a drawn link, no script error may fire, and the presses must add up to slides - 1 + steps.
// At each step the lit nodes and lines must be exactly the step's path, the lines before it done, and a path step
// must send its dots (data-repeat of them). Then, for the first pair of step slides side by side, presses ← from the
// later one's start to check that coming back fills the earlier one.
// Chrome as for shoot.ts.
// Usage: bun <skill dir>/steps.ts <port> <deck.html>
// Exit: 0 = every step plays / 1 = something above is off / 2 = nothing was checked (Chrome or the page failed).
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [port, deck] = process.argv.slice(2);
if (!port || !deck) {
  console.error("usage: bun steps.ts <port> <deck.html>");
  process.exit(2);
}
const fail = (message: string): never => {
  console.error(`steps: ${message}`);
  process.exit(2);
};
process.on("uncaughtException", (error) => fail(String(error)));
process.on("unhandledRejection", (error) => fail(String(error)));
setTimeout(() => fail("took longer than 5 minutes"), 300_000).unref();

const url = pathToFileURL(resolve(deck)).href;
const target = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, {
  method: "PUT",
  signal: AbortSignal.timeout(30_000),
})
  .then((response) => response.json())
  .catch((error: unknown) => fail(`Chrome on port ${port} did not answer: ${error}`));
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((ready, reject) => {
  ws.onopen = ready;
  ws.onerror = () => reject(new Error("could not open the DevTools connection"));
});

type Reply = { result?: { value?: unknown }; exceptionDetails?: unknown };
let lastId = 0;
const pending = new Map<number, (reply: Reply & { error?: { message: string } }) => void>();
ws.onmessage = (message) => {
  const reply = JSON.parse(String(message.data));
  pending.get(reply.id)?.(reply.result ?? { error: reply.error });
  pending.delete(reply.id);
};
const send = (method: string, params: object = {}) =>
  new Promise<Reply & { error?: { message: string } }>((done) => {
    lastId += 1;
    pending.set(lastId, done);
    ws.send(JSON.stringify({ id: lastId, method, params }));
  });
const evaluate = async (expression: string) => {
  const reply = await send("Runtime.evaluate", { expression, returnByValue: true });
  if (reply.error || reply.exceptionDetails)
    fail(`evaluate failed: ${JSON.stringify(reply.error ?? reply.exceptionDetails)}`);
  return reply.result?.value;
};

await send("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
// Listen for errors before the deck's own script runs, so an error while it loads counts too.
await send("Page.enable");
await send("Page.addScriptToEvaluateOnNewDocument", {
  source:
    "window.__errors = []; addEventListener('error', (e) => window.__errors.push(String(e.message))); addEventListener('unhandledrejection', (e) => window.__errors.push(String(e.reason)));",
});
await send("Page.navigate", { url });
const deadline = Date.now() + 20_000;
while (
  (
    await send("Runtime.evaluate", {
      expression: "document.readyState === 'complete' && !!document.fonts",
      returnByValue: true,
    })
  ).result?.value !== true
) {
  if (Date.now() > deadline) fail("the page did not finish loading in 20 s");
  await Bun.sleep(100);
}

const problems = (await evaluate(`[...document.querySelectorAll('.slide')].flatMap((s, i) => {
  const st = s.querySelector('.stage'); if (!st) return [];
  const at = 'slide ' + (i + 1) + ': ';
  if (!st.dataset.links) return [at + 'stage without data-links'];
  const all = [...st.querySelectorAll('[data-node]')].map((n) => n.dataset.node);
  const names = new Set(all);
  const out = all.filter((n, k) => all.indexOf(n) !== k).map((n) => at + 'duplicate node ' + n);
  const links = st.dataset.links.split(/\\s+/).filter(Boolean).map((p) => p.split('>'));
  const drawn = new Set(links.map((p) => p.slice().sort().join('|')));
  links.flat().filter((n) => !names.has(n)).forEach((n) => out.push(at + 'link to missing node ' + n));
  s.querySelectorAll('ol.steps li').forEach((li, k) => {
    const path = (li.dataset.path || li.dataset.light || '').split('>').filter(Boolean);
    if (!path.length) out.push(at + 'step ' + (k + 1) + ' has no path or light');
    path.filter((n) => !names.has(n)).forEach((n) => out.push(at + 'step ' + (k + 1) + ' names missing node ' + n));
    if (li.dataset.path) path.slice(1).forEach((n, h) => {
      if (!drawn.has([path[h], n].sort().join('|'))) out.push(at + 'step ' + (k + 1) + ' hops ' + path[h] + '>' + n + ' with no link');
    });
  });
  return out;
})`)) as string[];

const total = Number(await evaluate("document.querySelectorAll('.slide').length"));
const steps = Number(await evaluate("document.querySelectorAll('ol.steps li').length"));
const expected = total - 1 + steps;
const press = (key: string) =>
  evaluate(`document.dispatchEvent(new KeyboardEvent('keydown', { key: '${key}' })); true`);
// What the screen shows now: the slide in view, and for a step slide which line is marked now and how many nodes are lit.
const screen = async () =>
  (await evaluate(`(() => {
    const i = Math.round(document.querySelector('.deck').scrollTop / innerHeight);
    const s = document.querySelectorAll('.slide')[i];
    const items = [...s.querySelectorAll('ol.steps li')];
    const now = items.findIndex((li) => li.classList.contains('now'));
    const li = items[now];
    // What the step says should light: its path's nodes and, for a path, the lines between them.
    const path = li ? (li.dataset.path || li.dataset.light).split('>').filter(Boolean) : [];
    const wantNodes = [...new Set(path)].sort().join(',');
    const wantLines = li && li.dataset.path ? [...new Set(path.slice(1).map((n, h) => [path[h], n].sort().join('|')))].sort().join(',') : '';
    const litNodes = [...s.querySelectorAll('.node.lit')].map((n) => n.dataset.node).sort().join(',');
    const litLines = [...s.querySelectorAll('svg.links line.lit')].map((l) => l.dataset.pair).sort().join(',');
    const packets = s.querySelectorAll('.packet').length;
    // With reduced motion the deck sends no dots, by design.
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const wantPackets = li && li.dataset.path && !reduced ? Number(li.dataset.repeat) || 1 : 0;
    return { slide: i + 1, steps: items.length, now: now + 1,
      nowCount: items.filter((x) => x.classList.contains('now')).length,
      // The done lines must be exactly the ones before now, not just as many.
      done: items.every((x, k) => x.classList.contains('done') === (k < now)) ? now : -1,
      lightOk: litNodes === wantNodes && litLines === wantLines, packetsOk: packets === wantPackets,
      litNodes, wantNodes, litLines, wantLines, packets, wantPackets };
  })()`)) as {
    slide: number;
    steps: number;
    now: number;
    nowCount: number;
    done: number;
    lightOk: boolean;
    packetsOk: boolean;
  };

await press("Home");
let presses = 0;
let expectSlide = 1;
let expectStep = 0;
while (presses <= expected) {
  const shown = await screen();
  if (
    shown.slide !== expectSlide ||
    shown.now !== expectStep ||
    (expectStep > 0 && (shown.nowCount !== 1 || shown.done !== expectStep - 1 || !shown.lightOk || !shown.packetsOk))
  ) {
    problems.push(
      `after ${presses} presses: expected slide ${expectSlide} step ${expectStep}, screen shows ${JSON.stringify(shown)}`,
    );
    break;
  }
  if (shown.slide === total && expectStep === shown.steps) break;
  await press("ArrowRight");
  presses += 1;
  if (expectStep < shown.steps) expectStep += 1;
  else {
    expectSlide += 1;
    expectStep = 0;
  }
}
if (presses !== expected) problems.push(`${presses} presses reached the end, expected ${expected}`);

// Back from the first step of a step slide goes to the previous slide with all its steps out.
const back = (await evaluate(`[...document.querySelectorAll('.slide')].findIndex((s, i) => i > 0 &&
  s.querySelector('ol.steps') && document.querySelectorAll('.slide')[i - 1].querySelector('ol.steps'))`)) as number;
if (back > 0) {
  // back is 0-based, so dot [back] opens slide back + 1 (1-based) and ← should land on slide back with every step out.
  await evaluate(`document.querySelectorAll('.deck-dot')[${back}].click(); true`);
  await press("ArrowLeft");
  const shown = await screen();
  if (shown.slide !== back || shown.now !== shown.steps || shown.done !== shown.steps - 1 || !shown.lightOk)
    problems.push(`← into slide ${back} shows ${JSON.stringify(shown)}, expected all steps out`);
} else problems.push("no two step slides side by side, so coming back was not checked");

const errors = (await evaluate("window.__errors")) as string[];
problems.push(...errors.map((e) => `script error: ${e}`));
console.log(JSON.stringify({ presses, expected, problems }));
await fetch(`http://127.0.0.1:${port}/json/close/${target.id}`).catch(() => undefined);
process.exit(problems.length ? 1 : 0);
