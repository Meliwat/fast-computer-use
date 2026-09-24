# Release notes

## Unreleased

- Resolve repeated browser control names inside a named section, form, group or
  dialog. Preserve container identity across observation, focus and verification.
- Extension 0.4.6 includes 32 offline scope regressions; ambiguous or changing
  containers stop, and literal labels/payloads retain their meaning.

- Join nearby, aligned OCR lines belonging to one unnamed control. Duplicate,
  conflicting and low-confidence labels retain their existing checks.
- Include a generated-image visual diagnostic with an OCR-only mode. Its known
  confidence-related coverage miss is preserved in the documented results.

## v0.1.0 — 2026-09-24

First public developer preview of Fast Computer Use. The Mac app is named
Local Voice. Hold Option, speak, release, and see the transcript in a slim bar
at the top of the screen. Actions execute by default.

### Included

- On-device Apple speech recognition and local command models; no API key needed.
- App and website launching, supported new-chat/document actions, native menus.
- Chrome and macOS Accessibility control of identifiable fields and buttons.
- Browser search, typing, scrolling, dropdowns and standard ARIA widgets.
- Short explicit browser sequences with new observations between actions.
- Copying between named fields and changing existing text's case.
- OCR and the original GoClick vision model for constrained visual targeting.
- Pinned model assets, runtime installer, passive diagnostics and regression tests.

### Download and install

Use `local-voice-source-v0.1.0.tar.gz` with
`local-voice-command-models-2026-09-23.tar.gz`. Follow the root README.
The installer separately downloads pinned GoClick assets and Python dependencies.
`local-voice-runtime-notices-2026-09-23.tar.gz` preserves dependency notices;
it contains no runtime binaries and is not needed to run the app.
`SHA256SUMS` lists the three archives' SHA-256 digests.

Own source: MIT. Command checkpoints: modified Apache-2.0 BERT derivatives.
GoClick: upstream MIT. Dependency/model licenses and attribution remain intact.

### Preview boundaries

Apple Silicon, macOS 14+, Swift 6, native Python 3.11/3.12 and a code-signing
certificate are required. Chrome uses an unpacked extension (version 0.4.5).
There is no notarized binary or self-contained Python bundle in this release.
Only one development Mac has been tested; clean second-Mac onboarding is unverified.

This is not yet an arbitrary-goal computer agent. Requests need supported action
types and identifiable controls. Frames, closed shadow roots, canvases, unnamed
icons and ambiguous targets remain gaps. Some clicks/search submissions can be
delivered without verifying the intended result. The X search demo has a narrow
results adapter. Native copy/case actions still need live validation. Experimental
planners and fine-tuned visual models are excluded.

### Validation scope

The runtime baseline passed 90 Swift tests, 51 packaging/installation tests,
22 browser unit tests, 31 disclosure, 37 widget and 28 existing-text browser cases,
plus rich-text editor checks. These are authored fixtures, not universal app/site
compatibility or an end-to-end speech benchmark. The release smoke results are
also recorded in the GitHub release body.

Next: simpler installation, clean-Mac testing, broader language understanding,
visual grounding and verification of what happened after an action.
