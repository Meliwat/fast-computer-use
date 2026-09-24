# Standard interactive widgets — September 24, 2026

This records the controller 13 milestone. Controller 14 additionally supports
[explicit type wording](ROLE-LANGUAGE.md) and has 37 widget regression cases.
The original 35-case evidence below is retained unchanged.

Controller 13 / extension 0.4.3 discovers and activates custom menu items,
menu checkboxes/radios, switches, checkboxes, radio buttons, listbox options and
links. Native checkboxes and radios also support ordinary named clicks. These
are role-based capabilities, with no website names or selectors added.

Examples include `click Night mode` for a labeled switch or `click Compact`
for a radio/listbox choice. Existing operation classification remains in place;
adding controls does not establish understanding of every phrasing such as
“turn off…” or add new planning capabilities. A click toggles a control; it
does not imply a requested final boolean state. The explicit bridge `check`
operation separately requires a boolean and is idempotent when already set.

The resident grounded worker maps eligible activation roles to its existing
button/link representations. This extends known semantic aliases to these
widgets, after the same capability, enabled-state and confidence checks.
Weights and confidence thresholds are unchanged. Exact observed labels retain
their direct route; duplicate labels remain ambiguous.

## Outcomes and boundaries

Checkbox/radio/switch verification uses native checked/indeterminate state or
the appropriate ARIA checked state. Options can expose selected or checked state.
A click transition must remain consistent for 120 ms within the existing 500 ms
observation budget. A missing, malformed, unchanged or reversed state does not
prove success. A custom link or plain menu item may receive one click and still
report “result not verified” if it exposes no supported outcome. No retry occurs.

Explicit `check` validates the requested boolean before input, rejects malformed
initial state and verifies persistence for 180 ms. It now detects a native
checkbox becoming indeterminate after initially taking the requested value.
Native disabled fields and disabled/inert/ARIA-hidden ancestors, including open
shadow hosts, constrain availability. Plain text with a matching name does not
become clickable.

The implementation follows standard widget semantics described by the W3C
[switch](https://www.w3.org/WAI/ARIA/apg/patterns/switch/),
[radio](https://www.w3.org/WAI/ARIA/apg/patterns/radio/),
[menu](https://www.w3.org/WAI/ARIA/apg/patterns/menubar/) and
[listbox](https://www.w3.org/WAI/ARIA/apg/patterns/listbox/) patterns. It is not
a complete ARIA accessible-name engine or keyboard-navigation implementation.
Role widgets still need functional click handlers. Closed shadow roots,
canvas-only controls, unlabeled icons and large/truncated pages remain limited.

## Verification

[Portable evidence](tests/aria-evidence.json) records source hashes and outcomes.

- The original controller passed 2/32 initial full-contract cases. Most other
  cases were unsupported or abstained; this is not a count of wrong executions.
- The first implementation passed those 32. Review added three cases and found
  the delayed indeterminate-state error. After the fix, all 35 pass.
- Real resident models plus the headless controller pass 32 named, known-alias,
  negated and disabled cases across eight roles. The aliases were present in
  prior training, so this is transfer across widget roles, not unseen-concept
  generalization. Custom link outcomes remain explicitly unverified.
- Nine short model/controller sequences pass, including a menu item or switch
  revealing a field. These exercise a JavaScript harness, not the Swift sequence
  runner or microphone.
- All 120 earlier browser requests retain their per-case decisions and effects:
  57/66 supported requests complete, nine abstain, all 54 negative requests reject,
  and no wrong execution occurs in that authored set.
- Existing unit, disclosure, navigation, observer, text binding, X-result evidence
  and Chrome editing checks also pass.

Browser checks use disposable headless Chrome profiles with page networking
blocked. They do not establish live-site, speech or end-to-end native-host coverage.
The older 60 native live fixture cases remain historical evidence for unchanged
Swift sources. No new native/speech trial occurred in this revision.

Run the standalone widget check with `npm run test:aria`. The model harness is
`voice/research/grounded/verify-aria-model.cjs`; it accepts `--worker` for checking
the bundled worker, `--output` for a fresh report, and `PYTHON` /
`LOCALVOICE_MODEL_DIR` for the installed interpreter and bundled model directory.
The actual signed-bundle result is recorded in the evidence file.

## Fixture timing

The current regression runner uses controlled Chrome page time. It waits for
synchronous action start before advancing timers, and asserts that the clock
stays paused between commands. A hosted real-clock run had 36/37 passes because
the nominal 60 ms switch reversal occurred after a 129 ms verification window;
the independent later read correctly found the reverted state. The early-reversal
case remains unchanged and must reject under its specified timing. Production
verification budgets are unchanged. A verified effect describes the observed
interval, not a promise that a page will never change afterwards. Timing fields
from this fixture are simulated and must not be used as latency measurements.

See the [timing correction record](tests/aria-clock-evidence.json).

The shared harness also waits for `virtualTimeBudgetExpired` before ending a
clock interval. Returning as soon as the action promise resolved could leave an
older budget callback to pause the next action. A protocol lifecycle regression
failed before this correction, and widgets, disclosure and Swift sequence checks
pass with it. The test clock and production verification windows remain separate.
