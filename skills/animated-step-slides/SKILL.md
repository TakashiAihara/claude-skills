---
name: animated-step-slides
description: "Make a single-file HTML slide deck where each press of → moves a diagram one step - a dot travels along a path of nodes and the nodes and lines it passes light up - and slides switch instantly with no transition. Use it to write a spec document that explains how a system works (requests, data pipelines, jobs, protocols) one hop at a time. Comes with a template and two checkers (every slide fits the screen, every step plays). Trigger: animated slides, step slides, slides where the diagram moves, explain the flow step by step, 1 手ずつ動くスライド, アニメーションスライド."
---

# animated-step-slides

## Output

- One `.html` file: a spec document for people who need to understand how the system works, kept with the project's docs (e.g. `docs/slides/`). It is not a screen inside the product; the product's own UI serves a different reader
- The only external dependency is Google Fonts (drop the link to use system fonts); opening it in a browser is enough
- Each slide is one hand-written `<section class="slide">` and each step is one `<li>`, so a git diff shows what changed. Do not render slides from data with JS
- Nothing advances by itself. → (also ↓ Space PageDown, the wheel, a swipe, the button at the bottom right) shows the next step; when a slide's steps run out it goes to the next slide. ← goes back one step; going back into a slide shows all its steps. The dots on the right and Home / End jump to a slide and show it from its first step
- Only the diagram moves. Slides switch instantly: a sliding transition costs the reader attention, while a deck with no motion at all is just slides. With `prefers-reduced-motion` the dots are not sent but lighting still follows the steps

## Steps

1. Copy `template.html` (next to this file) to where the deck should live. Set `lang`, `<title>` and the comment on line 7 (where the facts came from, and the date)
2. Gather the facts from their source (code, config, docs) before writing. Copy numbers as the source states them. A caller that knows a domain (a repo's own skill) can do this part and hand the facts here
3. Replace the example slides between `<div class="deck">` and its closing tag. Keep the style and the script
4. Run the checks below. When a slide overflows, split it; do not cut its words to fit

## Writing a step slide

- Diagram: `<div class="stage" data-links="a>b b>c">` holding `<div class="node" data-node="a" style="left:16%;top:22%">name<small>note</small></div>`. `left` / `top` are the node's centre; keep them between 16% and 83% across, or the label leaves the box. The script draws a line for each pair in `data-links`
- Steps: each `<li>` of `<ol class="steps">` is one step, 3-7 per slide
    - `data-path="a>b>c>b"`: a dot travels through these nodes in order; the nodes and lines it passes light up. At least two nodes, and every hop must be a pair in `data-links`
    - `data-repeat="5"`: send 5 dots a little apart. Use it for a step that fetches or sends many times
    - `data-light="b"` (or `"b>c"`): send no dot, just light these nodes, no lines. Use it for a step that decides or reads without moving data
- Node names in steps and links must match `data-node` exactly; `steps.ts` fails otherwise
- Put two step slides side by side somewhere: `steps.ts` uses them to check ← (back into the earlier one with all its steps out, then one step back inside it)
- Keep slide changes instant; do not add `scroll-behavior: smooth`. Besides the reason above, `steps.ts` reads the screen right after each key
- Other blocks the template styles: `.split` + `.card` (two columns), `ul.plain`, `table` (in `.table-scroll`), `.meta-row` (small facts under a diagram), `.slide--title` / `.slide--divider`

## Checks

```bash
export SP=$(mktemp -d) PORT=9333
# in the background (on macOS the binary is "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
google-chrome --headless=new --no-sandbox --remote-debugging-port="$PORT" --user-data-dir="$SP/chrome" about:blank &
until curl -sf "http://127.0.0.1:$PORT/json/version" >/dev/null; do sleep 0.2; done
# <skill dir> is the directory holding this SKILL.md
bun <skill dir>/shoot.ts "$PORT" deck.html "$SP/shots"
bun <skill dir>/steps.ts "$PORT" deck.html
```

- `shoot.ts`: screenshots every slide at 1440x900 into the out dir and reports slides whose content leaves the screen or hides behind an inner scrollbar
    - Exit 0 = every slide fits / 1 = some slide is `OVERFLOW` / 2 = nothing was measured (no `.slide`, Chrome did not answer, the body font did not load, the page did not load in 20 s). Do not read 2 as 0
    - Control: append `1440 300` and it must exit 1
    - Run it again with `1280 720` appended (a common laptop screen); fitting at 1440x900 does not mean fitting there
    - Read the PNGs one by one for overlaps and crowding; the checker does not see an element hidden behind another, content clipped by an `overflow: hidden` box inside the slide, or which font weight loaded
- `steps.ts`: presses → from the first slide to the end. At each step the line marked now, the lit nodes and lines and the number of dots must match that step's path; every named node must exist, every hop must be a drawn line, no script error may fire, and the presses must equal slides - 1 + steps; entering a slide must show nothing lit, and → at the end must stay put. Then it checks ← into the earlier of two adjacent step slides and ← once more inside it. Wheel, swipe and the buttons are not driven; try them in a browser
    - Exit 0 = every step plays / 1 = something is off (the JSON lists it) / 2 = nothing was checked
- A dot in flight is not caught by either checker; press → through a few of the busiest slides in a browser
- Stop Chrome when done; its debug port can be driven by anyone on the host

## Not included

- Building from Markdown or data, speaker notes, export to PDF or video. The deck is plain HTML
