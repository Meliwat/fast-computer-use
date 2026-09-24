# Generic disclosure and toggle verification

September 23, 2026. Controller version 12, extension version 0.4.2.

Clicks on ordinary disclosure controls can now provide a verified transition
before the next short sequence step. This applies to HTML details/summary,
`aria-pressed` buttons, native popovers, and one explicitly linked `aria-controls`
surface. It does not require website-specific selectors or new model weights.

Summary text now contributes its accessible label, and only a details element's
first summary is treated as its native disclosure. Expanded/selected/pressed
values must use their valid state vocabulary. Related elements resolve inside
the control's own document or open shadow root; ambiguous references do not
provide verification. Changing the relationship or replacing a known related
element invalidates a previously bound observation before dispatch.

After one click, the verifier samples every 20 ms. A changed state must persist
for at least 120 ms within a 500 ms observation budget. Reversal, replacement or
contradiction after the first observed change stops verification. An explicit
expanded state must agree with its linked surface, and an opened surface must
be visibly available. No click is replayed. Unmeasurable ordinary buttons return
an unverified acknowledgement promptly; ordinary link navigation keeps its
existing immediate acknowledgement and separate URL verification path.

This confirms a specific control transition, not an arbitrary application task.
For example, an opened menu does not prove that selecting its next item will
save a file. Changes after the observation window, multiple linked surfaces,
closed shadow roots, frames and custom canvas widgets remain limitations. The
command model's operation vocabulary and confidence thresholds are unchanged.

## Evidence

The [saved baseline](tests/outcomes-baseline.json) passed six of 19 newly authored
cases with controller 11. Controller 12 passed those same 19 and twelve additional
cases, including shadow roots, lazy surfaces, removed surfaces, duplicate IDs,
cancelled popover opening, punctuation/non-ASCII IDs, and ARIA-hidden/inert
panels that remain visibly on screen. Interaction exclusion alone cannot verify
visual closure. The
[recorded evidence](tests/outcomes-evidence.json) includes all 31 results and
the exact source hashes. Each accepted action was independently inspected in
the fixture, and event counters checked that no action was repeated.

Two added real-local-model sequence scenarios now open a details section and
activate its newly revealed button, or open a popover and focus its field. All
seven model/controller sequence scenarios passed. This runner exercises actual
models and the DOM controller in headless Chrome; it does not invoke the Swift
sequence runner, native messaging or speech recognition.

All 120 repeated browser regression cases retained their previous per-case
correctness and fixture effects: 57/66 supported requests completed, 54/54
negative requests abstained, and nine supported requests still abstained.
There were no wrong executions. These authored/reused cases are development
evidence, not a real-site generalization score. Also passed: 22 browser unit
tests, four navigation, six observer, four text-binding and ten X-evidence
checks, plus the real Chrome editing-engine check.

On one matched stable-expanded-button fixture, 20 measured samples per controller
with alternating order and two excluded warmups gave these dispatch/verification
times:

| Controller | Median | p95 |
| --- | ---: | ---: |
| Version 11 | 191.2 ms | 194.2 ms |
| Version 12 | 132.2 ms | 134.2 ms |

This excludes fixture setup, speech, language-model parsing, IPC, native host and
real-site work. The app was not opened and no personal Chrome tabs were used.
The extension source is updated; live installed-extension behavior has not been
retested for this revision. Reload the unpacked extension when next trying it.

## Reproduce

These commands launch a separate headless Chrome with a temporary profile and
blocked page networking. They never attach to the personal browser:

```sh
node voice/browser/tests/outcomes-headless.cjs
node voice/browser/tests/benchmark-outcomes.cjs --baseline /path/to/version-11-controller.js --output /path/to/new-latency.json
```

The source-release package also exposes `npm run test:outcomes`. Diagnostic and
benchmark outputs accept new paths only, preserving existing evidence.
