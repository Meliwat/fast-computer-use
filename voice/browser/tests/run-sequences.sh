#!/bin/bash
set -eu
cd "$(dirname "$0")/../../.."
swift build --package-path voice
swiftc -parse-as-library -I voice/.build/debug/Modules \
  voice/.build/debug/VoiceCore.build/*.o \
  voice/tools/browser_sequence_check.swift -o voice/.build/browser-sequence-check
VOICE_SEQUENCE_CHECK="$PWD/voice/.build/browser-sequence-check" node voice/browser/tests/sequences-headless.cjs
