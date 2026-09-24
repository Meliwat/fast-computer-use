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

Full OCR-plus-GoClick validation is pending. This branch's evidence is generated
development data, not a general GUI accuracy or live voice-to-outcome benchmark.
No user's screen, microphone or application input is involved.

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
confidence-related refusal. The known 18/19 OCR result is therefore a failed
perfect-coverage run, not a claim that every case passed. CI compiles the tool
and runs the Swift contracts; it does not supply model weights or run this
coverage diagnostic.
