# Developer Guide

How this repository is built, what you edit, what gets generated, and the
workflow to get a change onto your Glove80. This is the developer-facing
companion to `README.md` (which is the end-user keymap guide).

---

## The big picture

This repo is a **keymap source project**, not a firmware build. It transforms
hand-written source into a `keymap.dtsi` blob that you paste into the **MoErgo
Glove80 Layout Editor**, which then builds the actual `.uf2` firmware in the
cloud.

```
                 ┌─────────────── you edit ───────────────┐
                 │  keymap.dtsi.erb   device.dtsi          │
                 │  world.yaml  emoji.yaml  keymap.json    │
                 └────────────────────┬────────────────────┘
                                      │  rake  (local: Ruby/ERB + Graphviz)
                                      ▼
                 ┌──────────── generated text ─────────────┐
                 │  keymap.dtsi   define.svg/.json          │
                 │  README/*.pdf   (*.min intermediates)    │
                 └────────────────────┬────────────────────┘
                                      │  sync into keymap.json, then IMPORT it
                                      ▼
              MoErgo Glove80 Layout Editor  (my.moergo.com)
                                      │  cloud build (ZMK + dtc + Zephyr)
                                      ▼
                       firmware .uf2  ──►  _build/  ──►  ./flash  ──►  keyboard
```

> **Deploy method used here: JSON import.** This repo is deployed by importing
> `keymap.json` into the Layout Editor (the editor only imports JSON, not DTSI
> files). The firmware builds from `keymap.json`'s embedded
> `custom_defined_behaviors` (the `keymap.dtsi` text) and `custom_devicetree`
> (the `device.dtsi` text), so those must be **synced into `keymap.json` before
> import**. `rake` does *not* do this sync — see
> [Workflow A](#workflow-a--changing-behavior--settings-the-common-case).

> **Key fact:** nothing in this repo compiles firmware. `rake` only produces
> **text**. The `.uf2` is compiled by MoErgo's cloud. See
> [Firmware build boundary](#firmware-build-boundary).

---

## Editable files (source of truth)

Edit **these**, then rebuild.

| File | What it is | Edit it to change… |
|------|-----------|--------------------|
| **`keymap.dtsi.erb`** | The core source. ~2200-line ERB template that emits the C-preprocessor DTSI keymap: behaviors, home-row mods, hold-taps, combos, macros, layer logic, and the tunable `#define` settings block at the top. | Almost everything: key **behaviors**, timing, difficulty level, OS default, forgiveness flags, mouse settings, combos, macros. **~90% of edits happen here.** |
| **`device.dtsi`** | Per-key RGB layer/mod indicators. Hand-edited despite the `.dtsi` extension (there is no `device.dtsi.erb`). | Per-key lighting / RGB indicators. |
| **`world.yaml`** | Unicode "World" characters (codepoints / shift & modifier transforms). | Add/change Unicode characters. |
| **`emoji.yaml`** | Emoji characters. | Add/change emoji. |
| **`keymap.json`** | The **fully-assembled active keymap** (32 layers, "Glorious Engrammer v52"), exported from the Layout Editor. Its `custom_defined_behaviors` holds the pasted `keymap.dtsi` and `custom_devicetree` holds the pasted `device.dtsi` (this is why it is ~692 KB). | **Which key does what, per layer**; base-layer letter arrangement; **which alpha layouts are enabled**. Edited via the Layout Editor GUI (export → overwrite), *not* by hand. See [Changing key assignments / layouts](#workflow-b-changing-key-assignments-or-enabled-layouts). |
| `define.dot.erb` | Template for the settings-dependency Graphviz diagram. | Rarely — only to change that diagram. |
| `layouts/*.json` | Standalone **reference** base-layer templates (ColemakDHm, Dvorak, QWERTY, …). 3 layers each, empty behaviors. **Not read by the build** — they are starting points to import into the editor. | Nothing automatic; copy-paste sources only. |

There are **two representations of "the keymap"**, and confusing them is the
most common mistake:

- **Source** = `keymap.dtsi.erb` → generates `keymap.dtsi` (the *behaviors*).
- **Assembled snapshot** = `keymap.json` (the *layers + a pasted copy of the
  behaviors*). The firmware is built from `keymap.json`'s embedded strings.

Editing `keymap.dtsi.erb` and running `rake` updates `keymap.dtsi` but **not**
the copy embedded in `keymap.json`. The paste-back step is what closes the loop.

---

## Emitted files (generated — do NOT hand-edit)

`rake` overwrites these. Hand-edits are lost on the next build.

| File | Generated from | Purpose |
|------|----------------|---------|
| **`keymap.dtsi`** | `keymap.dtsi.erb` + `keymap.json` + `keymap.zmk` + `*.yaml` | **The artifact you paste into the Layout Editor.** Committed even though generated. |
| `*.dtsi.min` | `keymap.dtsi`, `device.dtsi` | Minified intermediates for the diagrams (gitignored; removed by `rake clean`). |
| `define.dot` → **`define.svg`** | `define.dot.erb` + `*.dtsi.min` | Settings-dependency diagram. |
| **`define.json`** | `*.dtsi.min` | Extracted `#ifndef` **fallback** defaults (handy read-only summary of every default setting). |
| `README/*-layer-diagram.pdf` → **`README/all-layer-diagrams.pdf`** | `README/*.png` | Merged printable layer maps. |

Also **machine-produced, do not treat as source**:

- **`keymap.zmk`** — full ZMK output emitted by the Layout Editor. The build
  only mines it for `#define POS_[LR]H_*` key-position constants.
- **`default.json`** — reference export of the factory default layout; unused by the build.

---

## Commands — what, where, when

Run all commands from the repo root.

| Command | When to use it | Requires |
|---------|----------------|----------|
| `rake` | Rebuild **everything** (`:dtsi` + `:dot` + `:pdf`) after any source edit. | Ruby, rake, graphviz, graphicsmagick, poppler-utils |
| `./rake` | Same, but runs `rake` inside Docker — use if you don't have the tools installed. Auto-builds the image from `Dockerfile`. | Docker |
| `rake keymap.dtsi` | Regenerate **only `keymap.dtsi`** (the file target). Ruby-only. Use when you only touched behaviors. ⚠️ Plain `rake dtsi` does **not** build `keymap.dtsi` — the `:dtsi` task depends on the `.erb`, and `keymap.dtsi` is built transitively via the `.min` → `dot`/`pdf` chain. | Ruby, rake |
| `rake dot` | Regenerate `define.svg` / `define.json`. | + graphviz |
| `rake pdf` | Regenerate the layer-diagram PDFs. | + graphicsmagick, poppler-utils |
| `rake clean` | Remove `*.tmp` / `*.min` and intermediate PDFs. | — |
| `rake clobber` | Also remove generated `.min` / merged PDF outputs. | — |
| `./flash` | Copy the newest `_build/*.uf2` onto a mounted Glove80 in bootloader mode. **Does not build** the `.uf2`. | Linux; `inotifywait`; a `.uf2` already in `_build/` |

**Non-interactive Docker note:** the `./rake` wrapper uses `docker run -it`,
which fails when there is no TTY (scripts/automation). In that case invoke the
container directly:

```sh
IMAGE=${PWD##*/}:$(git hash-object Dockerfile)
docker run --rm -u $(id -u):$(id -g) -v "$PWD:/opt" "$IMAGE" rake dtsi
```

**About PDF churn:** re-running `rake pdf` rewrites the layer PDFs with new
binary metadata even when nothing visually changed. If a `git diff` shows only
`README/all-layer-diagrams.pdf` flipping bytes at the same size, discard it
(`git checkout README/all-layer-diagrams.pdf`) and `rake clean` the intermediates.

---

## The development workflow

### Workflow A — changing behavior / settings (the common case)

For anything defined in `keymap.dtsi.erb` (timings, home-row mods, combos,
macros, `#define` settings, OS default, etc.):

1. **Edit** `keymap.dtsi.erb` (or `world.yaml` / `emoji.yaml` / `device.dtsi`).
2. **`rake keymap.dtsi dot`** to regenerate `keymap.dtsi` (plain `rake dtsi`
   does **not** build it — see [Commands](#commands--what-where-when)).
3. **Review the diff** — `git diff keymap.dtsi` — confirm only what you intended changed.
4. **Sync** the generated text into `keymap.json`'s embedded fields (the step
   that makes the JSON import carry your change):
   ```sh
   ruby -rjson -e 'k=JSON.load_file("keymap.json"); k["custom_defined_behaviors"]=File.read("keymap.dtsi"); k["custom_devicetree"]=File.read("device.dtsi"); File.write("keymap.json", JSON.pretty_generate(k))'
   ```
5. **Import `keymap.json`** in the Layout Editor and **build** (MoErgo compiles
   the `.uf2` in the cloud). *(Alternatively you can paste `keymap.dtsi` into the
   "Custom Defined Behaviors" box and `device.dtsi` into the devicetree box —
   but this repo deploys by JSON import.)*
6. **Download** the `.uf2` into `_build/`, then **`./flash`** with the keyboard
   in bootloader mode.
7. **Commit** `keymap.dtsi` + `keymap.json` together so the repo stays in sync.
   (If you rearranged keys/layers *inside the editor*, re-export and overwrite
   `keymap.json`, then re-run `rake` + the sync in step 4.)

> Quick tuning without a rebuild: many `#define` settings can be overridden by
> adding lines at the **top of the "Custom Defined Behaviors" box** in the
> editor. Good for experiments; fold the final values back into
> `keymap.dtsi.erb` so the source is the source of truth.

### Workflow B — changing key assignments or enabled layouts

Anything about *which behavior sits on which physical key / layer*, the base
letter arrangement, or *which alpha layouts are enabled/default* lives in
`keymap.json` and is edited through the **Layout Editor GUI**, not by hand:

1. In the Layout Editor, enable **Settings → Advanced → "Enable local config"**.
2. Rearrange keys / add / reorder / rename base layers there.
3. **Export** (Download) the keymap JSON and **overwrite `keymap.json`**.
4. **`rake`** — the ERB re-derives the base-layer `KEY_*` aliases and the
   `LAYER_<name>` guards from the new `keymap.json`.
5. Paste the regenerated `keymap.dtsi` back into the editor, build, flash.
6. Commit `keymap.json` + `keymap.dtsi` together.

**Enabled alpha layouts:** the ERB counts every layer positioned **before the
`Typing` layer** as an alpha layout
(`ALPHA_LAYERS_COUNT = layer_names.find_index("Typing")`). The **boot default is
layer index 0**. Runtime switching is the `Magic` layer number row
(`&to 0..3` at positions 10–13). Only **7 raw numeric layer indices** exist in
`keymap.json` (3 `&tog`, the 4 Magic `&to` switchers) — all other layer
references are symbolic `LAYER_<name>`, which survive reordering.

### Recipe: add or reorder a base alpha layout

This is the exact, proven procedure (used in v52 to make Colemak-DH the default).
The scripted version lives in **`tools/reorder-base-layout.rb`** (a documented
worked example — copy and adapt its constants for the next change).

1. **Derive the new base layer from an existing *assembled* base layer in
   `keymap.json`** — e.g. copy the `Colemak` layer and remap only the letter
   keys. **Do NOT graft from `layouts/*.json`:** those templates fill the
   F-row / number / arrow positions that the assembled base layers deliberately
   leave as `&none`, so ~30–47 positions differ and a direct copy is wrong.
2. **Apply the letter changes** on the copied layer, and **rename
   `LAYER_<old>` → `LAYER_<new>`** throughout *that layer's* bindings. Keeping
   the layer name, its home-row `LAYER_<name>` args, and (after `rake`) its
   `== 0` guard all in agreement is what avoids the `dtc` footgun below.
   *(Colemak → Colemak Mod-DH is six swaps: pos 27 `G→B`, 39 `D→G`, 40 `H→M`,
   50 `V→D`, 51 `B→V`, 59 `M→H`.)*
3. **Reorder `layer_names` and `layers` together.** Layers before `Typing` are
   the enabled alpha layouts; **index 0 is the boot default**.
4. **Fix the 7 numeric layer-index refs** (all in the `Magic` layer): the 3
   `&tog` values (remap by which layer they point to) and the 4 `&to` alpha
   switchers at positions 10–13 (set explicitly; point unused ones at `&none`).
   Nothing else needs touching — all other layer access is symbolic.
5. **Write with `JSON.pretty_generate` and no trailing newline** — that is
   byte-for-byte the Layout Editor's export format (a plain load→dump round-trip
   is identical), so the git diff stays limited to your real change.
6. **Regenerate and verify:**
   ```sh
   rm -f keymap.dtsi keymap.dtsi.min device.dtsi.min
   IMAGE=${PWD##*/}:$(git hash-object Dockerfile)
   docker run --rm -u $(id -u):$(id -g) -v "$PWD:/opt" "$IMAGE" rake keymap.dtsi dot
   docker run --rm -u $(id -u):$(id -g) -v "$PWD:/opt" "$IMAGE" rake clean
   grep -oE 'defined\(LAYER_[A-Za-z_]+\) && LAYER_[A-Za-z_]+ == 0' keymap.dtsi   # guards == your alpha set
   grep -Ec 'LAYER_<removed1>\b|LAYER_<removed2>\b' keymap.dtsi                  # want 0 dangling
   ```
7. **Sync into `keymap.json`:** `ruby tools/sync-keymap-json.rb`.
8. **Import `keymap.json`** in the Layout Editor and **build** to validate —
   `dtc` runs only in MoErgo's cloud (see below).

### Recipe: enable same-hand thumb + modifier chords (e.g. Cmd+Space)

**Goal:** hold a home row mod and tap a thumb key **on the same hand** —
right `Cmd+Space`, `Cmd+Tab`, `Shift+Enter` — the way v36 allowed. v52's
bilateral enforcement blocks this by design. Implemented in v52 for the three
right-hand thumbs; `tools/enable-same-hand-thumb-mods.rb` is the worked example.

**The key insight** (from sunaku's [home row mods] write-up): bilateral
enforcement is **two levels**, and you must change *both* — fixing only one
does nothing (this is the mistake we made first: level 1 alone had zero effect
on hardware).

1. **Level 1 — the positional gate.** Every home row mod carries
   `hold-trigger-key-positions = <OPPOSITE_HAND_KEYS>` (`keymap.dtsi.erb`,
   inside the `emit_home_row_mod` block). A mod only resolves to a *hold* when
   the next key pressed is in that list — same-hand keys make it resolve to a
   *tap* instead. Since the thumb clusters are split by hand
   (`LEFT_HAND_KEYS` / `RIGHT_HAND_KEYS`), a right-hand mod never held for a
   right-thumb tap. **Fix:** the `#define SAME_HAND_THUMB_MODS` toggle
   (`keymap.dtsi.erb` line 6) appends the mod's *own-hand* thumb positions
   (`LEFT_THUMB_KEYS` / `RIGHT_THUMB_KEYS`) to that list. Requires `rake
   keymap.dtsi dot` + `ruby tools/sync-keymap-json.rb` (it lives in the
   generated DTSI / `custom_defined_behaviors`).

2. **Level 2 — the per-finger enforcement layers.** When a mod *does* hold, it
   also flips on a per-finger layer (`layer_names` 5–12: `LeftPinky`…
   `RightPinky`) that **re-defines every same-hand key** while the mod is held:
   same-hand alphas run a `&*_tap` macro that cancels the mod, and the thumbs
   were remapped to `&mo LAY_RH_T*` — so the thumb's keycode never reached the
   OS and the chord silently failed **even after the Level 1 fix**. **Fix:**
   set the same-hand thumb positions to `&trans` on those layers, so the press
   falls through to the base layer's thumb behavior, wrapped by the held mod.
   This is exactly how the **opposite-hand** thumbs already behave (they are
   `&trans` there — which is why opposite-hand chords always worked). This is a
   `keymap.json` `layers`-array edit only, so **no `rake`/sync is needed** for
   it. The v52 change set Enter (pos 57), Tab (73), Space (74) to `&trans` on
   the four right-hand layers (indices 9–12), covering whichever right finger
   holds the mod.

**Validation:** `rake` cannot prove this works — flash and test the actual
chords on hardware. (We confirmed `Cmd+Space` / `Cmd+Tab` / `Shift+Enter`.)

[home row mods]: https://sunaku.github.io/home-row-mods.html#same-hand-chords

---

## Firmware build boundary

Because it trips people up:

- `rake` **cannot** produce a `.uf2`. No Zephyr, no `west`, no ARM toolchain,
  no `config/`/`boards/`/CI in this repo. The `Dockerfile` installs only
  `ruby rake graphviz graphicsmagick poppler-utils`.
- The `.uf2` is compiled by **MoErgo's cloud** when you build in the Layout Editor.
- `./flash` only **copies** an already-downloaded `.uf2` from `_build/`.
- Therefore **`rake` succeeding does not mean the keymap compiles.** Devicetree
  errors (`dtc`) only surface in MoErgo's cloud build.

---

## Gotcha: base-layer name ↔ `LAYER_<name>` consistency

For each base (alpha) layer, three things must all use the **same** name — the
layer's `layer_names` entry (MoErgo auto-generates `#define LAYER_<name>` from it):

1. The home-row bilateral hold-taps in that layer:
   `&LeftPinky/…/RightPinky (KEY, LAYER_<name>)` — the 2nd arg token-pastes onto
   `LeftPinky_layer` to select the variant, so it must expand to the base layer
   index (0).
2. The `#if defined(LAYER_<name>) && LAYER_<name> == 0` guard in
   `custom_defined_behaviors` that defines the `KEY_LH_*` / `KEY_RH_*` aliases.

If these disagree (e.g. the base layer is renamed to `ColemakDHm` but the
bindings/guard still say `LAYER_Colemak`), MoErgo's `dtc` fails with
`parse error: expected number or parenthesized expression` on that layer's long
`bindings = <…>` line — and `rake` will **not** catch it.

**Do not** patch just the one binding token. The proven fix is to start from a
working layout with a consistent name and only remap the letter keys (rather
than renaming the layer). Regenerating with `rake` after a correct `keymap.json`
edit keeps the guard and `KEY_*` aliases consistent automatically.
