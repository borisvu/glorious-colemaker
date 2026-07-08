# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository. For a fuller human-facing walkthrough of the file roles, commands, and workflow, see [DEVELOPMENT.md](DEVELOPMENT.md).

## What this is

A personal fork of [sunaku/glove80-keymaps](https://github.com/sunaku/glove80-keymaps) (the "Glorious Engrammer" keymap for the MoErgo Glove80). `origin` is `borisvu/glorious-colemaker`; `upstream` is sunaku's repo — pull improvements from upstream and layer personal customizations on top. The keymap is authored/built here and pasted into the MoErgo Glove80 Layout Editor; it is not flashed directly from a normal ZMK build.

## Build

`rake` regenerates all derived files. There is no test suite — validation is compiling and flashing to the keyboard.

```sh
rake            # native: needs ruby, rake, graphviz, graphicsmagick, poppler-utils
./rake          # same, but inside Docker (auto-builds the image from Dockerfile)
rake clean      # remove *.tmp and *.min intermediates
rake clobber    # also remove generated .min / pdf outputs
```

Default task runs three groups: `:dtsi` (the keymap), `:dot` (settings diagram), `:pdf` (layer diagrams). Run a single group with e.g. `rake dtsi`.

`./flash` copies the newest `_build/*.uf2` to a mounted Glove80 bootloader (Linux paths; expects `inotifywait`).

### Firmware build boundary (important)

**This repo does NOT compile firmware.** `rake` only produces *text* (`keymap.dtsi` + the diagram SVG/PDF/JSON). There is no Zephyr/`west`/ARM toolchain here (the `Dockerfile` installs only ruby/rake/graphviz/graphicsmagick/poppler-utils), and no `west.yml`/`build.yaml`/`config/`/`boards/`/CI. The `.uf2` is built by **MoErgo's cloud service** behind the Glove80 Layout Editor once you paste `keymap.dtsi` in. `./flash` only *copies* an already-downloaded `.uf2` from `_build/` — nothing here writes `_build/`. Consequence: the `LAYER_<name>` footgun below surfaces as a `dtc` error in MoErgo's cloud build, not locally — `rake` succeeding does **not** prove the keymap compiles.

## Deploy workflow

1. Edit source (`keymap.dtsi.erb`, `world.yaml`, `emoji.yaml`, `device.dtsi`, or `keymap.json`).
2. Run `rake`.
3. Copy the regenerated **`keymap.dtsi`** contents into the "Custom Defined Behaviors" text box of your keymap in the Glove80 Layout Editor.

## Architecture

The core keymap is a large C-preprocessor DTSI program generated from an ERB template, then consumed by the Layout Editor (which runs it through the ZMK/dtc toolchain). Everything is compile-time: layout behavior is selected via `#define` settings (operating system, `DIFFICULTY_LEVEL`, home-row-mod order/timing, forgiveness flags, mouse keys, etc.) documented at the top of `keymap.dtsi.erb` and in README.md.

### Source files (edit these)
- **`keymap.dtsi.erb`** — the main source: ~2200 lines of ERB emitting the preprocessor keymap (behaviors, home row mods, layers, macros). This is where nearly all keymap logic lives.
- **`device.dtsi`** — per-key RGB layer/mod indicators (hand-edited, not generated despite the `.dtsi` extension).
- **`world.yaml`** / **`emoji.yaml`** — Unicode "World" characters and Emoji; the ERB reads these to generate `&world_*` / emoji behaviors. See README "World and Emoji characters" for the codepoints/characters/transforms schema.
- **`keymap.json`** — the active, fully-assembled keymap ("Glorious Engrammer v52", 32 layers) exported from the Layout Editor. The ERB parses it to learn the base layer's alpha arrangement and key positions. Re-export and overwrite this after rearranging the base layer, then `rake`. **This is the only JSON whose `custom_defined_behaviors` (the pasted `keymap.dtsi`) and `custom_devicetree` (the pasted `device.dtsi`) are populated** — hence its ~692 KB size. It is a full round-trip snapshot; the firmware ultimately builds from these embedded strings, so editing `keymap.dtsi` alone does not change the keyboard until it is pasted back and re-exported.
- **`define.dot.erb`** — template for the settings-dependency Graphviz diagram.
- **`layouts/*.json`** — standalone **reference** base-layer templates (ColemakDHm, Colemak, Dvorak, Engrammer, Enthium, Halmak, Norman, QWERTY, Workman), 3 layers each (base + Lower + Magic), with **empty** `custom_defined_behaviors`. **Not consumed by the build** — nothing in the Rakefile/ERB references `layouts/`; they are import-into-editor starting points, not working keymaps on their own.
- **`default.json`** — standalone reference export of the factory "default" layout; not used by the build.

### Which alpha layouts are "enabled" / the base layout
The ERB treats **every layer positioned before `Typing`** as an alpha layout: `ALPHA_LAYERS_COUNT = layer_names.find_index("Typing")` (`keymap.dtsi.erb:127`). Currently enabled (layers 0–3): Enthium, Dvorak, Colemak, QWERTY. The **boot/default base layer is index 0**. Runtime switching is done by the `Magic` layer's number-row keys (`keymap.json` positions 10–13 → `&to 0..3`). Only **7 raw numeric layer-index references** exist in `keymap.json` (3 `&tog`, the 4 Magic `&to` switchers) — everything else references layers symbolically via `LAYER_<name>`, which MoErgo regenerates from `layer_names`. Those 7 are what break on a layer reorder. Reordering/adding base layouts is a `keymap.json` change that goes through the Layout Editor (see `README.md` → "Rearranging the base layer") and cannot be validated locally.

### Generated files (do NOT hand-edit; `rake` overwrites them)
- **`keymap.dtsi`** ← `keymap.dtsi.erb` + `keymap.json` + `keymap.zmk` + `*.yaml`. This is the artifact you paste into the Layout Editor. It is committed even though generated.
- **`*.dtsi.min`** — minified keymap/device DTSI (gitignored); intermediate for the diagrams.
- **`define.dot` → `define.svg`**, and **`define.json`** — settings graph and extracted defaults (parsed from `#ifndef`/`#define` defaults in the minified DTSI).
- **`README/*-layer-diagram.pdf` → `README/all-layer-diagrams.pdf`** — merged printable layer maps (converted from the committed `README/*.png`).

### `keymap.zmk`
Full ZMK output emitted by the Glove80 Layout Editor. Machine-generated. The Rakefile only reads it to extract `#define POS_[LR]H_*` key-position constants (`POS_BY_KEY` / `KEY_BY_POS`).

## Gotcha: base-layer name / `LAYER_<name>` consistency

Three things must all reference the **same** base-layer name (the layer's `layer_names` entry, from which MoErgo auto-generates `#define LAYER_<name>`):
1. The home-row bilateral hold-taps: `&LeftPinky/…/RightPinky (KEY, LAYER_<name>)` — the 2nd arg token-pastes onto `LeftPinky_layer` to pick the variant, so it must expand to the base layer index (0).
2. The `#if defined(LAYER_<name>) && LAYER_<name> == 0` guard in `custom_defined_behaviors` that defines the `KEY_LH_*` / `KEY_RH_*` position aliases.

If these disagree (e.g. base layer renamed to `ColemakDHm` but bindings/guard still say `LAYER_Colemak`), dtc fails with `parse error: expected number or parenthesized expression` on that layer's long `bindings = <…>` line. Do **not** fix this by rewriting just the binding token — start from a working layout with a consistent name and only remap the letter keys. Base-layout switchers live on the `Magic` layer's number row as `&to <numeric index>` (these break on layer reorder).
