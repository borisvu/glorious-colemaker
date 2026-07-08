#!/usr/bin/env ruby
# frozen_string_literal: true
#
# reorder-base-layout.rb — REFERENCE / WORKED EXAMPLE (not idempotent)
# =====================================================================
#
# This is the exact transform used in v52 to make Colemak-DH the default base
# layout (ColemakDHm, Enthium, QWERTY; Dvorak + plain Colemak removed) and set
# macOS as the OS. It is kept as a documented recipe for the NEXT base-layout
# change. It asserts the STARTING state (Enthium/Dvorak/Colemak/QWERTY/macOS),
# so it will refuse to run again as-is — copy it and adapt the constants.
#
# See DEVELOPMENT.md → "Recipe: add or reorder a base alpha layout" for the
# full rationale. The general procedure this encodes:
#
#   1. Derive a NEW base layer from an EXISTING assembled base layer in
#      keymap.json (NOT from layouts/*.json — those fill the F-row/number/arrow
#      positions that assembled base layers leave as &none, so they don't graft).
#   2. Apply the letter swaps and rename LAYER_<old> -> LAYER_<new> throughout
#      that one layer (keeps name/args/guard consistent -> avoids the dtc
#      "expected number" footgun; see the LAYER_<name> memory / DEVELOPMENT.md).
#   3. Reorder layer_names + layers together. Layers BEFORE "Typing" are the
#      enabled alpha layouts; index 0 is the boot default.
#   4. Fix the only 7 raw numeric layer-index refs (all in the Magic layer):
#      3x &tog (remap by layer identity) and 4x Custom "&to N" switchers
#      (set by position). Everything else references layers symbolically
#      (LAYER_*, LAY_*) and survives reordering untouched.
#   5. Write with JSON.pretty_generate and NO trailing newline (byte-compatible
#      with the Layout Editor's export format).
#
# AFTER running this: regenerate and sync (rake does NOT sync into keymap.json):
#
#     rm -f keymap.dtsi keymap.dtsi.min device.dtsi.min
#     IMAGE=${PWD##*/}:$(git hash-object Dockerfile)
#     docker run --rm -u $(id -u):$(id -g) -v "$PWD:/opt" "$IMAGE" rake keymap.dtsi dot
#     docker run --rm -u $(id -u):$(id -g) -v "$PWD:/opt" "$IMAGE" rake clean
#     ruby tools/sync-keymap-json.rb          # copies keymap.dtsi/device.dtsi into keymap.json
#
# Then IMPORT keymap.json in the Layout Editor and BUILD (only the cloud dtc can
# validate it; a successful rake does NOT prove it compiles).

require 'json'

FILE = "keymap.json"
km = JSON.load_file(FILE)
names = km["layer_names"]
layers = km["layers"]
raise "unexpected start order (adapt this script)" unless
  names[0] == "Enthium" && names[1] == "Dvorak" && names[2] == "Colemak" &&
  names[3] == "QWERTY" && names[4] == "macOS"

deep = ->(o) { JSON.parse(JSON.generate(o)) }

# ---- 1. Build ColemakDHm base layer from the working Colemak layer ----
colemak = layers[names.index("Colemak")]
dh = deep.(colemak)

# Colemak -> Colemak Mod-DH: six letter swaps (all simple &kp X keys).
# pos => [expected_current_letter, new_letter]
LETTER_SWAPS = { 27 => %w[G B], 39 => %w[D G], 40 => %w[H M],
                 50 => %w[V D], 51 => %w[B V], 59 => %w[M H] }
LETTER_SWAPS.each do |pos, (from, to)|
  b = dh[pos]
  raise "pos #{pos}: expected &kp, got #{b["value"]}" unless b["value"] == "&kp"
  raise "pos #{pos}: expected #{from}, got #{b["params"][0]["value"]}" unless b["params"][0]["value"] == from
  b["params"][0]["value"] = to
end

# Rename LAYER_Colemak -> LAYER_ColemakDHm everywhere in this layer.
rename = ->(o) {
  case o
  when Hash   then o.each { |k, v| o[k] = rename.(v) }; o
  when Array  then o.map! { |v| rename.(v) }; o
  when String then o.gsub("LAYER_Colemak", "LAYER_ColemakDHm")
  else o
  end
}
rename.(dh)

# ---- 2. New layer order (Dvorak + Colemak removed; ColemakDHm at 0) ----
NEW_ORDER = %w[ColemakDHm Enthium QWERTY macOS Typing
               LeftPinky LeftRingy LeftMiddy LeftIndex RightIndex RightMiddy RightRingy RightPinky
               Gaming Cursor Number Function macOS_left Symbol Mouse System macOS_right
               Emoji World Factory Lower macOS_lower Mouse_slow Mouse_fast Mouse_warp Magic]

content = { "ColemakDHm" => dh }
names.each_with_index { |nm, i| content[nm] = layers[i] unless %w[Dvorak Colemak].include?(nm) }

new_names  = NEW_ORDER.dup
new_layers = NEW_ORDER.map { |nm| content.fetch(nm) { raise "missing layer #{nm}" } }

# ---- 3. Fix the 7 numeric layer-index refs (all in the Magic layer) ----
old_index_to_new = ->(old_num) {
  nm = names[old_num] or raise "no old layer at #{old_num}"
  new_names.index(nm) or raise "layer #{nm} not in new order"
}
magic = new_layers[new_names.index("Magic")]

# &tog <num>: remap by layer identity (Factory 25->24, macOS 4->3)
magic.each do |b|
  b["params"][0]["value"] = old_index_to_new.(b["params"][0]["value"].to_i) if b["value"] == "&tog"
end

# Magic alpha switchers at pos 10..13 (Custom "&to N") — set by position.
set_switcher = ->(pos, to, label, icon, desc) {
  b = magic[pos]
  raise "pos #{pos} not a Custom &to/&none switcher" unless b["value"] == "Custom" &&
    b.dig("params", 0, "value").to_s.start_with?("&to ", "&none")
  b["params"][0]["value"] = to
  b["decoration"] = { "label" => label, "icon" => icon, "description" => desc }
}
set_switcher.(10, "&to 0", "Base",  "fa-0", "Switch to base alpha layout #0: Colemak-DH (default).")
set_switcher.(11, "&to 1", "Alpha", "fa-1", "Switch to alpha layout #1: Enthium.")
set_switcher.(12, "&to 2", "Alpha", "fa-2", "Switch to alpha layout #2: QWERTY.")
set_switcher.(13, "&none", "",      "fa-3", "(unused)")

# ---- 4. Validate before writing ----
raise "layer count != 31 (#{new_layers.length})" unless new_layers.length == 31
new_layers.each_with_index { |l, i| raise "layer #{i} wrong key count #{l.length}" unless l.length == 80 }
blob = JSON.generate(new_layers)
%w[Colemak Dvorak].each do |base|
  n = blob.scan(/LAYER_#{base}(?!DHm)\b/).length
  raise "#{n} dangling LAYER_#{base} refs remain" if n > 0
end
{ 27 => "B", 39 => "G", 40 => "M", 50 => "D", 51 => "V", 59 => "H" }.each do |pos, l|
  got = new_layers[0][pos]["params"][0]["value"]
  raise "ColemakDHm pos #{pos} expected #{l} got #{got}" unless got == l
end

km["layer_names"] = new_names
km["layers"] = new_layers
File.write(FILE, JSON.pretty_generate(km)) # no trailing newline: matches editor export

puts "OK: #{new_names.length} layers; alpha = #{new_names[0...new_names.index('Typing')].join(', ')}"
puts "Now regenerate keymap.dtsi and run tools/sync-keymap-json.rb (see header)."
