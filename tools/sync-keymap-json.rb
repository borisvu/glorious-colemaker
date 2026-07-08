#!/usr/bin/env ruby
# frozen_string_literal: true
#
# sync-keymap-json.rb — copy the generated keymap.dtsi and device.dtsi into
# keymap.json's embedded fields so the JSON is ready to IMPORT into the MoErgo
# Layout Editor.
#
# Why: the Layout Editor imports keymap.json (not DTSI files), and the firmware
# builds from keymap.json's `custom_defined_behaviors` (= keymap.dtsi text) and
# `custom_devicetree` (= device.dtsi text). `rake` regenerates keymap.dtsi but
# does NOT write it back into keymap.json — this script does.
#
# Usage (after `rake keymap.dtsi dot`):
#     ruby tools/sync-keymap-json.rb
#
# Idempotent: run it any time; re-running with no source change is a no-op diff.

require 'json'

km = JSON.load_file("keymap.json")
before_b = km["custom_defined_behaviors"]
before_t = km["custom_devicetree"]
km["custom_defined_behaviors"] = File.read("keymap.dtsi")
km["custom_devicetree"]        = File.read("device.dtsi")
JSON.parse(JSON.generate(km)) # sanity: still serializable
File.write("keymap.json", JSON.pretty_generate(km)) # no trailing newline: matches editor export

changed = [before_b != km["custom_defined_behaviors"], before_t != km["custom_devicetree"]]
puts "synced keymap.json  (custom_defined_behaviors changed=#{changed[0]}, custom_devicetree changed=#{changed[1]})"
puts "OS in keymap.dtsi: #{km["custom_defined_behaviors"][/#define OPERATING_SYSTEM '.'/]}"
puts "Now import keymap.json in the Layout Editor and build."
