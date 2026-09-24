# Selecting controls by name and type — September 24, 2026

Controller 14 / extension 0.4.4 and the updated local command worker preserve
explicit control types during grounding. `Click Notifications link` selects an
observed link, while `Click Notifications checkbox` selects an observed checkbox.
Different kinds of controls can share a label without forcing an ambiguous
selection when the request specifies the type. The unqualified duplicate remains
ambiguous. A named control of the wrong type does not cause a click on another label.

The shared worker recognizes suffixes such as `radio button`, `menu item`,
`switch`, `checkbox`, `option`, `tab`, `button`, `link`, `field` and `box`, plus
forms such as `the link called Notifications`. Literal observed names such as
`Help link`, `Radio settings` and `Switch` remain labels. A role noun is excluded
from separate label matching so an unrelated control named `Link` cannot confuse
`Notifications link`. `Search` remains the name in `Focus the Search field`.

Only the role noun is normalized to the existing classifier vocabulary. The
operation verb, negation and requested name remain. The original role hint
filters observed controls before binding or semantic ranking. The same
normalization applies to sequence preflight. Confidence thresholds, model weights,
supported operations and the local-only inference path are unchanged.

The DOM observation now distinguishes native input checkboxes and radios from
generic inputs. Bound identities include the native input type: changing a
checkbox to a radio invalidates an earlier binding, even when an explicit ARIA
role remains the same. Native Accessibility capability restrictions are unchanged.

## Evidence

The [portable result record](tests/role-language-evidence.json) includes failures,
final outcomes and exact source hashes.

- A fixed 28-case model/controller diagnostic initially passed 10/28, with ten
  wrong-type activations and eight supported requests abstaining. Those were
  headless diagnostic actions, not observed user-session failures. The corrected
  worker passes all 28, with no wrong actions.
- An additional 23 review cases cover negation, unsupported deletion, disabled
  homonyms, role-word collisions, literal labels, prefix wording and punctuation.
  All **51 combined cases pass** using the real local models and headless browser.
- The actual rebuilt signed bundle passes the same 51 cases. Thirty-two earlier
  named/semantic widget cases also pass against its worker.
- All 120 previous browser requests retain their exact decisions/effects:
  57/66 supported requests complete; nine abstain; all 54 negatives reject.
- The 60 native-style language cases retain 56/60 correct decisions, including
  all 31 negative rejections. One intermediate change regressed `Search field`;
  its failed result is preserved, and the final version restores the old result.
- All 37 widget cases, nine sequence cases, 31 grounded Python tests and the
  existing browser unit/disclosure/navigation/observer/text/X/editor checks pass.

These are authored development/regression cases. They do not establish arbitrary
language understanding, visual appearance-based role recognition, live website
coverage or microphone latency. A control styled like a button may expose a
different semantic role. Ambiguous or unsupported phrasing can still abstain.
Unverified click outcomes still stop a sequence; no retry is introduced.

## Reproduce

The role diagnostic uses the installed parser interpreter and model directory:

```sh
PYTHON=/path/to/parser-python LOCALVOICE_MODEL_DIR=/path/to/models node voice/research/grounded/probe-role-language.cjs --review --output /path/to/fresh-report.json
```

Use `--worker /path/to/grounded/worker.py` to exercise the bundled copy. It starts
only a local worker and disposable headless Chrome, with page networking blocked.
No personal browser, native app window, microphone, screen capture or desktop
input is used. Native checks described here are language probes, not new live
Accessibility tests. Reload the extension and relaunch the app for a live trial.
