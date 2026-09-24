# Local command models connected to native controls

The existing local operation classifier and target ranker can now act on the
foreground native window. No app-specific selectors, new model weights, cloud
calls or generated code were added. Exact command rules remain first.

Examples, when the named controls are visible:

- “Bring up Preferences” — model selects the observed Preferences button.
- “Let me type into Subject” — model selects and focuses the Subject field.
- “Focus City” — direct native focus, independent of model confidence.
- “Click the Subject field” — exact click lookup can fall through to model-based
  field focus when the label describes an editor.
- “Focus Subject then type hello” — the existing command queue handles exact
  focus and literal typing; a failed first action clears pending actions.

Chrome retains its browser adapter. Native learned commands are enabled by
default along with website grounding; `--no-grounded-commands` disables both
learned control paths while retaining exact native focus/fill/type commands.
If native operation preflight abstains, the previous learned app-command parser
remains the fallback. It was separately checked on the fixture's two negated/
question requests and abstained on both; broader language errors remain possible.

## Observation and execution

Swift collects visible buttons, links, menu buttons and text controls from the
focused window or its one active sheet. It checks actual AX capabilities and
system hit-testing. The snapshot is complete within a limit of 2,000 nodes,
350 ms and 48 visible candidates; exceeding a limit stops the proposal.

Only labels, roles, geometry and capability/state flags reach the local worker.
Editable text is not sent to the model or used as a label. Text labels include
placeholders and explicit linked captions. Native AX references stay in Swift
behind ephemeral IDs, using the browser observation wire format.

The controller validates the worker's request/snapshot IDs, operation, confidence,
target identity and capabilities. A binding is consumed once, even if execution
fails. Before input, a new AX scan must agree on the window/sheet identity,
window geometry, focused element, complete control set, target labels, geometry
and capabilities. Bindings expire after two seconds. Cancellation clears them.

Learned activation currently presses buttons/links/menu buttons; it does not
infer a desired checkbox/radio state. Explicit named native clicks retain their
existing behavior. Field focus must persist for at least 120 ms to be verified.
Focus does not insert or submit text; later dictation uses the existing literal
insertion and stable read-back path.

Button presses use a bounded 350 ms acknowledgement timeout because ordinary
AppKit animation exceeded the earlier 50 ms attribute-read timeout. An uncertain
acknowledgement never triggers a retry. When AX exposes no selected/expanded/
check-state transition, the result is **“Click delivered; result not verified.”**
An arbitrary delay cannot verify that outcome, so those buttons incur no extra
180 ms sleep. Controls exposing a measurable transition retain their read-back.

An unresolved exact click can still use vision. Model proposal failure can fall
through before input, but native action failure cannot: the action may already
have occurred. No fallback repeats an attempted native action.

## Live disposable-form check, September 23

All **20 cases passed** through the signed app with existing Accessibility access.
The fixture independently recorded callbacks, focused fields and value history.
Exactly one Preferences press and one Save as press occurred; Open, Save, Help,
duplicate and disabled buttons were not pressed. Only Subject received text.

| Successful case | Time | App-reported result |
| --- | --- | --- |
| Bring up Preferences | 106 ms | Click delivered; result not verified |
| Bring up Save as, beside Save | 165 ms | Click delivered; result not verified |
| Let me type into Subject | 220 ms | Field focus verified |
| Focus City, through its placeholder | 257 ms | Field focus verified |
| Click Subject field through normal fallback | 194 ms | Field focus verified |
| Literal dictation after focus | 199 ms | Text inserted and read back |

The remaining cases rejected duplicate fields/buttons, disabled fields/buttons,
read-only and password fields, hidden and absent targets, negation, a question,
replay, a renamed target, an expired binding and cancellation. Negative field
cases use the exact focus path, exercising native checks instead of depending
on classifier abstention.

The first run identified two issues. A Save as callback occurred despite an AX
timeout, prompting the acknowledgement fix without retrying. “Focus City”
abstained in the classifier, prompting the generic exact focus route. It was not
relabeled as a model success. The complete suite was rerun after both fixes.

Times are individual M1 Pro/macOS 15.5 runs, including observation, local model
work where applicable, execution and verification. They exclude microphone/ASR
and cold worker startup. The fixture calls shared final-text/model/dispatch code;
it does not simulate physical Option holding or the entire speech scheduler.
Independent callbacks prove these test-button effects; production correctly
leaves arbitrary button outcomes unverified. Both apps were closed afterward.
The Swift suite passed 82 tests and the signed full build passed.
[Recorded evidence](native-grounding-evidence.json)

## Reproduce

Close Local Voice first. This developer command briefly focuses a disposable
form. It uses the existing AX grant, starts no microphone or screen capture,
closes its fixture/app paths and attempts to restore the previously focused app.

```sh
sh voice/build.sh
sh voice/research/native/build-text-fixture.sh
python3 voice/research/native/run-text-check.py --grounded
```

The flag-free runner remains the earlier native fill/type regression suite.

This is standard AppKit control evidence, not coverage of all native apps.
A subsequent [native menu integration](NATIVE-MENUS.md) adds menu-bar and
visible-item traversal. Unexposed controls, custom canvas editors, large control
trees, native semantic multi-step plans and general visual outcomes remain
unfinished. Vision remains required in the full build; this path does
not replace visual understanding or the outstanding live visual trial.
