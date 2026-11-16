// Screenshots every slide of a deck through Chrome's DevTools protocol and reports slides whose content leaves the
// viewport or hides behind an inner scrollbar. Start Chrome first:
//   google-chrome --headless=new --no-sandbox --remote-debugging-port=<port> --user-data-dir=<dir> about:blank
// Usage: bun <skill dir>/shoot.ts <port> <deck.html> <out-dir> [width] [height]
// Exit: 0 = every slide fits / 1 = some slide overflows / 2 = nothing was measured (no slides, Chrome or CDP failed).
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [port, deck, outDir, width = "1440", height = "900"] = process.argv.slice(2);
if (!port || !deck || !outDir) {
  console.error("usage: bun shoot.ts <port> <deck.html> <out-dir> [width] [height]");
  process.exit(2);
}

const fail = (message: string): never => {
  console.error(`shoot: ${message}`);
  process.exit(2);
};
if (!(Number(width) > 0 && Number(height) > 0)) fail(`width and height must be positive numbers: ${width} ${height}`);
const STEP_TIMEOUT_MS = 30_000;

// Exit 1 means overflow only; any crash is "nothing was measured".
process.on("uncaughtException", (error) => fail(String(error)));
process.on("unhandledRejection", (error) => fail(String(error)));

mkdirSync(outDir, { recursive: true });
const url = pathToFileURL(resolve(deck)).href;
const target = await fetch(`http://127.0.0.1:${port}/json/new?${url}`, {
  method: "PUT",
  signal: AbortSignal.timeout(STEP_TIMEOUT_MS),
})
  .then((response) => response.json())
  .catch((error: unknown) => fail(`Chrome on port ${port} did not answer: ${error}`));
if (typeof target?.webSocketDebuggerUrl !== "string") fail("Chrome returned no target");

const ws = new WebSocket(target.webSocketDebuggerUrl);
type Reply = { data?: string; result?: { value?: unknown }; exceptionDetails?: unknown };
let lastId = 0;
const pending = new Map<number, { done: (result: Reply) => void; reject: (error: Error) => void }>();
ws.onmessage = (message) => {
  const reply = JSON.parse(String(message.data));
  const waiter = pending.get(reply.id);
  if (!waiter) return;
  pending.delete(reply.id);
  if (reply.error) waiter.reject(new Error(`${reply.error.message} (${reply.error.code})`));
  else waiter.done(reply.result ?? {});
};
ws.onclose = () => {
  for (const waiter of pending.values()) waiter.reject(new Error("the DevTools connection closed"));
};
await new Promise((ready, reject) => {
  ws.onopen = ready;
  ws.onerror = () => reject(new Error("could not open the DevTools connection"));
  ws.addEventListener("close", () => reject(new Error("the DevTools connection closed while opening")));
  setTimeout(() => reject(new Error(`the DevTools connection did not open in ${STEP_TIMEOUT_MS} ms`)), STEP_TIMEOUT_MS);
}).catch((error: unknown) => fail(String(error)));

const send = (method: string, params: object = {}) =>
  new Promise<Reply>((done, reject) => {
    lastId += 1;
    const id = lastId;
    const timer = setTimeout(() => {
      pending.delete(id);
      reject(new Error(`${method} took longer than ${STEP_TIMEOUT_MS} ms`));
    }, STEP_TIMEOUT_MS);
    pending.set(id, {
      done: (result) => {
        clearTimeout(timer);
        done(result);
      },
      reject: (error) => {
        clearTimeout(timer);
        reject(error);
      },
    });
    ws.send(JSON.stringify({ id, method, params }));
  });
const evaluate = async (expression: string) => {
  const reply = await send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
  if (reply.exceptionDetails) throw new Error(`evaluate failed: ${JSON.stringify(reply.exceptionDetails)}`);
  return reply.result?.value;
};

try {
  await send("Emulation.setDeviceMetricsOverride", {
    width: +width,
    height: +height,
    deviceScaleFactor: 1,
    mobile: false,
  });
  // The marker lives on the current document only, so its absence proves the reload committed a new one.
  await evaluate("window.__shootOld = true");
  await send("Page.reload");
  // Page.reload returns before the new document commits, so wait for the deck's own URL to finish loading. Web fonts
  // change line breaks, and fonts.ready also settles when the font's stylesheet never arrived (no face to wait for), so
  // the body's first font family must be a face that actually loaded; otherwise the fallback font would be measured.
  // Poll from here rather than inside the page: an evaluate started on the old document dies with it, so each try is
  // short and a destroyed context is just another try.
  const ready = `!window.__shootOld && location.href === ${JSON.stringify(url)} && document.readyState === 'complete'`;
  const deadline = Date.now() + 20_000;
  while ((await evaluate(ready).catch(() => false)) !== true) {
    if (Date.now() > deadline) fail("the page did not finish loading in 20 s");
    await Bun.sleep(100);
  }
  const loaded = await evaluate(`new Promise((done) => {
    document.fonts.ready.then(() => {
          const family = getComputedStyle(document.body).fontFamily.split(',')[0].trim().replace(/['"]/g, '');
          const faces = [...document.fonts].filter((face) => face.family.replace(/['"]/g, '') === family);
          // A body font on the system has no face; a body family that a linked stylesheet asks for but that has no face means the stylesheet did not arrive.
          const asked = [...document.querySelectorAll('link[rel="stylesheet"]')].some((link) =>
            decodeURIComponent(link.href).split('+').join(' ').includes('family=' + family));
          const loaded = faces.some((face) => face.status === 'loaded') || (!faces.length && !asked);
          // Every other web font the slides use (a family with declared faces) must have loaded a face too.
          const used = new Set([...document.querySelectorAll('.slide, .slide *')].map((el) =>
            getComputedStyle(el).fontFamily.split(',')[0].trim().replace(/['"]/g, '')));
          const missing = [...used].filter((name) => {
            const faces = [...document.fonts].filter((face) => face.family.replace(/['"]/g, '') === name);
            return faces.length > 0 && !faces.some((face) => face.status === 'loaded');
          });
          done(!loaded ? 'the body font ' + family + ' did not load' : missing.length ? 'fonts did not load: ' + missing.join(', ') : 'ok');
    });
    setTimeout(() => done('the fonts did not finish loading in 20 s'), 20000);
  })`);
  if (loaded !== "ok") fail(String(loaded));
  // A deck that sets scroll-behavior: smooth would be measured mid-scroll on the wrong slide.
  await evaluate("document.querySelectorAll('*').forEach((el) => { el.style.scrollBehavior = 'auto'; }); true");

  const count = Number(await evaluate("document.querySelectorAll('.slide').length"));
  if (!Number.isInteger(count) || count < 1) fail(`no .slide in ${deck}`);

  let overflowing = 0;
  for (let i = 0; i < count; i++) {
    const info = (await evaluate(`(() => {
      const slide = document.querySelectorAll('.slide')[${i}];
      slide.scrollIntoView({ behavior: 'instant' });
      const box = slide.getBoundingClientRect();
      if (Math.abs(box.top) > 1 || Math.abs(box.left) > 1) return { misplaced: true, heading: (slide.querySelector('h1,h2') || {}).textContent };
      // The screenshot is the viewport, so a slide taller or wider than it is cut off however its content sits.
      const tooBig = box.height > innerHeight + 1 || box.width > innerWidth + 1 ? 1 : 0;
      // Every side: a centred column that grows too tall spills out of the top as much as the bottom.
      const outside = [...slide.querySelectorAll('*')].filter((el) => {
        const r = el.getBoundingClientRect();
        return r.width > 0 && (r.top < box.top - 1 || r.left < box.left - 1 || r.bottom > box.bottom + 1 || r.right > box.right + 1);
      }).length;
      // A slide is read without scrolling, so content behind any inner scrollbar counts as cut off too.
      const scrolled = [slide, ...slide.querySelectorAll('*')].filter((el) =>
        el.scrollHeight > el.clientHeight + 1 && getComputedStyle(el).overflowY !== 'visible' ||
        el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflowX !== 'visible').length;
      return { outside: outside + tooBig, scrolled, heading: (slide.querySelector('h1,h2') || {}).textContent };
    })()`)) as { outside: number; scrolled: number; heading: string; misplaced?: boolean };
    if (info.misplaced) fail(`slide ${i + 1} (${info.heading}) did not scroll into the viewport`);
    const shot = await send("Page.captureScreenshot", { format: "png" });
    if (!shot.data) fail(`no screenshot for slide ${i + 1}`);
    await Bun.write(`${outDir}/slide-${String(i + 1).padStart(2, "0")}.png`, Buffer.from(shot.data ?? "", "base64"));
    const bad = info.outside > 0 || info.scrolled > 0;
    if (bad) overflowing += 1;
    console.log(
      `${i + 1}\t${bad ? `OVERFLOW (outside ${info.outside}, scrolled ${info.scrolled})` : "ok"}\t${info.heading}`,
    );
  }
  await fetch(`http://127.0.0.1:${port}/json/close/${target.id}`).catch(() => undefined);
  ws.close();
  process.exit(overflowing > 0 ? 1 : 0);
} catch (error) {
  fail(String(error));
}
