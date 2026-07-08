#!/usr/bin/env ruby
# frozen_string_literal: true
#
# enable-same-hand-thumb-mods.rb — let a RIGHT-hand home row mod combine with a
# RIGHT-hand thumb key (Space / Tab / Enter) so one-handed shortcuts such as
# Cmd+Space, Cmd+Tab and Shift+Enter work again (they did in v36, but v52's
# bilateral enforcement blocks them).
#
# Background — bilateral enforcement is TWO levels:
#   1. `hold-trigger-key-positions` on each home row mod (edited in
#      keymap.dtsi.erb via the SAME_HAND_THUMB_MODS #define) decides whether the
#      mod resolves as a HOLD. Same-hand thumb positions were added there.
#   2. When a mod holds it also flips on a per-finger "enforcement layer"
#      (RightIndex/RightMiddy/RightRingy/RightPinky, layer indices 9-12). On that
#      layer every SAME-hand key is re-defined: alphas cancel the mod, and the
#      thumbs were remapped to `&mo LAY_RH_T*` — so the thumb keycode never
#      reached the OS and the chord silently failed.
#
# The opposite-hand thumbs on those layers are already `&trans` (pass-through),
# which is exactly why opposite-hand mod+thumb chords work. This script gives the
# three same-hand thumbs the identical `&trans` treatment. Combined with the ERB
# change, the mod now holds AND the thumb falls through to its base behavior,
# wrapped by the modifier.
#
# Scope (intentionally minimal — see conversation): only Space/Tab/Enter on the
# RIGHT hand. Not idempotent: it asserts the current `&mo LAY_RH_T*` bindings and
# refuses to run if they are already changed.
#
# After running: import keymap.json into the MoErgo Layout Editor and build.
# (No `rake`/sync needed — this only touches the `layers` array, not the
# generated DTSI. The ERB/DTSI change was synced separately.)

require "json"

Dir.chdir(File.expand_path("..", __dir__))

# layer index => expected layer name (guards against a layer reorder)
RIGHT_ENFORCEMENT_LAYERS = {
  9  => "RightIndex",
  10 => "RightMiddy",
  11 => "RightRingy",
  12 => "RightPinky",
}.freeze

# key position => [human label, expected current binding]
TARGETS = {
  57 => ["Enter", "&mo LAY_RH_T1"],
  73 => ["Tab",   "&mo LAY_RH_T5"],
  74 => ["Space", "&mo LAY_RH_T4"],
}.freeze

TRANS = { "value" => "&trans" }.freeze

km = JSON.load_file("keymap.json")
names = km.fetch("layer_names")

RIGHT_ENFORCEMENT_LAYERS.each do |idx, expected_name|
  actual = names[idx]
  unless actual == expected_name
    abort "ABORT: layer #{idx} is #{actual.inspect}, expected #{expected_name.inspect} " \
          "(did the layers get reordered? update RIGHT_ENFORCEMENT_LAYERS)."
  end

  layer = km.fetch("layers").fetch(idx)
  TARGETS.each do |pos, (label, expected_binding)|
    binding = layer[pos]
    current = binding.is_a?(Hash) ? binding.dig("params", 0, "value") : binding
    unless current == expected_binding
      abort "ABORT: #{expected_name} pos #{pos} (#{label}) is #{current.inspect}, " \
            "expected #{expected_binding.inspect} — refusing to overwrite."
    end
    layer[pos] = TRANS.dup
    puts "  #{expected_name.ljust(11)} pos #{pos} (#{label.ljust(5)}): #{expected_binding} -> &trans"
  end
end

JSON.parse(JSON.generate(km)) # sanity: still serializable
File.write("keymap.json", JSON.pretty_generate(km)) # no trailing newline: matches editor export
puts "\nDone. Import keymap.json in the MoErgo Layout Editor and build."
