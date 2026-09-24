# Generic native field filling

The native path now supports `fill Destination with Oslo` in the foreground
app, using its current Accessibility tree. Chrome keeps its existing browser
editing path. There is no per-app selector or model request for native filling.

Fields can be named through their title, description, help, placeholder or
explicitly linked caption. An optional `field`, `text box` or `input` suffix is
accepted after attempting the literal label first. A linked AppKit caption can
have role `AXUnknown`; its explicit label relationship and non-writable text
are used instead of requiring `AXStaticText`. Current editable-field contents
are never used as target labels.

## Selection and execution

- Search the foreground app's focused window or active sheet, with a bounded
  traversal. A truncated search rejects instead of guessing uniqueness.
- Require one visible, enabled, writable, non-protected field. Confirm visibility
  with a system Accessibility hit-test. Duplicate, hidden, disabled, read-only,
  protected and missing targets stop before input.
- Focus the identified element through Accessibility. Recheck the app, window,
  element identity, label, capability, visibility and original value before writing.
- Replace its value once and place the caret at the end when supported. Repeating
  the same fill verifies the value without another write. Filling never submits.
- Observe the expected value and unchanged focus for at least 180 ms, with a
  500 ms overall observation limit. Reversion, unexpected text or focus loss
  stops verification. No second write or automatic retry is attempted.

Existing native `type …` insertion now uses the same stability check, preserving
selection/cursor and Unicode handling. Its existing Paste fallback rechecks the
field after searching for the menu item, before touching the clipboard.

This is bounded Accessibility support, not universal editor support or a visual
understanding model. Fields must expose the necessary text and writable/focus
attributes. Exact names are required; generalized native paraphrase grounding,
canvas editors and arbitrary multi-step native goals remain unfinished.

## Live evidence, September 23

The signed production app executed the fixed parser/dispatch/Accessibility path
against a separate disposable AppKit form. All 14 cases passed. The form recorded
its own value history, independently of the app's AX read-back:

| Check | Result | Time |
| --- | --- | --- |
| Named fill | `Original` → `Oslo` | 224 ms |
| Unicode insertion | `Oslo` → `Oslo👋` | 210 ms |
| Literal fill value | `Oslo and open Notes`, without another command | 224 ms |
| Repeated same fill | Verified; no additional value change | 233 ms |
| Placeholder + role suffix | City field → `Paris` | 247 ms |
| Linked caption | Subject → `Hello` | 252 ms |
| Six missing/ambiguous/unavailable target cases | Rejected; other fields untouched | 25–34 ms |
| Delayed text reversion | `Original` → `Changed` → `Original`; rejected | 132 ms |
| Focus moves after write | One write observed; verification rejected | 115 ms |

The last two cases deliberately receive the initial write before their simulated
failure. Rejection does not mean that no effect occurred. Neither was retried.
The password field's value was never included in the fixture report.

These are individual runs on an M1 Pro with macOS 15.5. Timings include selection,
input and read-back, but exclude speech recognition and startup. No microphone,
screenshots, network requests or model workers were used. This proves this form
and these native controls, not every app. Both apps were closed after the check.
The Swift suite passed 81 tests, and the signed full build passed.

An initial run stopped before input because the fixture wasn't foreground. The
launcher now waits for confirmed foreground state. The expanded linked-caption
case initially failed because AppKit reported `AXUnknown`; the production label
reader was corrected and the full suite rerun. See [recorded evidence](native-text-evidence.json).

## Reproduce the live fixture check

Close Local Voice first. This developer check temporarily opens and focuses a
disposable form. It uses the existing signed app's Accessibility permission,
requests no grants, and attempts to restore the previous app on exit if the user
has not switched elsewhere. It never types into a personal app.

```sh
sh voice/build.sh
sh voice/research/native/build-text-fixture.sh
python3 voice/research/native/run-text-check.py
```

Each run writes a fresh report under `.cache/native-text`, verifies the fixture's
own history and protected-field counters, and closes only its fixture/app paths.
On a failure, inspect the report before repeating input. The test is explicit;
ordinary launch never opens this fixture or enables this diagnostic mode.
