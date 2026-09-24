# Wrapped visual labels

An unnamed accessibility control can now gain a visible label from several OCR
lines. For example, `Account` above `preferences` becomes `Account preferences`.
This extends the existing visual fallback across apps; it adds no site adapter
or trained model.

Each line must still meet the 0.8 OCR confidence threshold, sit completely
inside the same enabled control, and intersect no other control. Existing
accessibility names take precedence. Lines are ordered from top to bottom and
joined only when they form a nearby vertical stack with overlapping horizontal
extent. Overlapping rows, separate columns, large gaps and combined labels over
300 characters reject. Confidence is a recognizer score, not a calibrated
correctness probability.

GoClick must still place its point inside the independently identified control.
Window, pixels, accessibility identity and hit target are rechecked before a
press. Duplicate names still need disambiguation. A press acknowledgement does
not establish that the requested application outcome happened.

## Development evidence

All 95 Swift tests pass, including new cases for reading order, three-line
labels, separated/overlapping text, length bounds, duplicate names and conflicting
accessibility labels. The new positive assertions failed before the change.

The generated-image diagnostic contains the original twelve scenes plus three
wrapped positive labels and four negative cases. Local accurate Apple OCR and
label binding produce 18/19 expected target decisions: both `Account preferences`
and `Create a new workspace` become usable. The `Create new chat` case remains
unresolved: OCR reads the words correctly but assigns `new chat` confidence 0.5,
so the existing threshold refuses that line. The case and failure are retained;
no threshold was lowered. All nine negative cases abstain.

The full OCR-plus-GoClick run produced the same 18/19 decisions: nine of ten
positive targets selected and all nine negative requests declined. Every accepted
model point falls inside its expected control. The original twelve cases retain
their results; the two newly supported wrapped labels also agree with GoClick.
The unresolved case never reaches model decoding because its full label lacks
sufficient OCR evidence. Negative cases also stop at label binding; this does
not demonstrate that GoClick itself recognizes absent targets.

[Complete evidence](multiline-text-evaluation.json) preserves both runs, including
the miss and their nonzero exit codes. An independent audit checked image hashes,
case counts, unchanged compiled-source hashes, model asset hashes and accepted
point geometry. CPU training ran concurrently; component timings are not clean
speed comparisons. These are generated development fixtures, not general GUI
accuracy or live voice-to-outcome measurements. No user's screen, microphone or
application input is involved.

## Reproduce

Build the included diagnostic from the repository root:

```sh
swift build --package-path voice
swiftc -parse-as-library -I voice/.build/debug/Modules \
  voice/.build/debug/VoiceCore.build/*.o \
  voice/.build/debug/VoicePerception.build/*.o \
  voice/tools/visual_grounding_check.swift -o /tmp/localvoice-visual-check
/tmp/localvoice-visual-check --ocr-only /tmp/localvoice-ocr-new
```

The OCR-only mode needs no app bundle or model weights. To also require the
original model's point agreement, replace `--ocr-only` with the path to a built
`Local Voice.app`. It reads that bundle's worker/model resources without opening
the app. Choose a new output directory for each run; existing results are never
overwritten. Each directory contains generated PNGs and `report.json` with
recognized text, confidence, composed labels and per-case results.

The diagnostic exits nonzero when any expected target is missed, including a
confidence-related refusal. The known 18/19 result therefore includes a missed
target. CI compiles the tool
and runs the Swift contracts; it does not supply model weights or run this
coverage diagnostic.
