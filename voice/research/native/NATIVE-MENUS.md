# Generic native menu control

The native command path now observes menu-bar headers and currently visible menu
items. It uses the foreground app's Accessibility tree and hit-testing, without
app names, prewritten menu paths, screenshots or new model weights.

Examples in a native app with the corresponding menus:

- “Open the File menu.”
- “Click Save as.”
- “Click Export menu,” followed by “click Image.”
- “Close menu.”

Exact menu commands use the direct path. Natural phrasing such as “Bring up File
menu” or “Bring up Save as” can use the existing local operation classifier and
target ranker. The spoken label may omit a trailing ellipsis. A `menu` or `menu
item` suffix distinguishes that role. Chrome keeps its existing browser route.

## Observation and dispatch

Closed menu definitions are not candidates. AX exposes those names even when
they are hidden, and enumerating them can call AppKit menu delegates. This path
requires visible bounds and ownership of the system hit-test result; delegate
callbacks are not treated as proof of visibility.

While a menu is open, observations include its visible menu chain and menu-bar
headers. Window controls behind it are excluded. Native filling, typing, sending
and visual clicking also check for an active menu. Recently observed surfaces
are retained only while still visible, covering the closing animation after
AXSelected clears, including a cancelled command.

Exact clicks keep the existing window-control path when no menu is open. Menu
matching requires a unique label across visible items, including disabled ones.
The local models share the existing ephemeral IDs, two-second expiry, one-use
bindings and complete scene revalidation. A new snapshot must agree before any
input. Menu observation is bounded to 800 nodes, 128 entries and 350 ms; the
combined learned observation retains its 48-candidate limit.

Opening is reported verified only after the child menu becomes visible.
Selecting an item sends one AXPress, then observes closure for up to 500 ms.
Closure requires the selected-menu state to clear and the previously visible
surfaces to disappear for 60 ms. Dismissal similarly sends one AXCancel and
checks closure. Cancellation or an uncertain acknowledgement never repeats an
action. A command may already have occurred when cancelled after acknowledgement.

**A closed menu does not prove that Save, Export or another command succeeded.**
The app explicitly reports that the menu command was delivered and leaves its
application-level result unverified.

## Live disposable fixture, September 23

All **26 menu cases passed** through the signed app. The fixture independently
recorded exactly Save as, Image and Save, in that order. Save intentionally tests
cancellation after acknowledgement. All window buttons and all field values
remained untouched. The suite checks hidden definitions, duplicate/disabled
items, background controls, replay, stale scenes, cancellation, submenus,
idempotent opening, actual dismissal and restored field focus.

| Case | Measured time |
| --- | ---: |
| Open File through the exact command | 84 ms |
| Open File through the local models | 173 ms |
| Open Export submenu | 68 ms |
| Save as through the local models, including closure | 448 ms |
| Select Image, including submenu closure | 473 ms |
| Dismiss and verify closure | 110 ms |

These are individual warm M1 Pro/macOS 15.5 measurements, including observation,
dispatch and the stated verification. Model routes include operation preflight
and target selection. Microphone, speech recognition and cold startup are
excluded. Menu-item timings include AppKit's closing animation. Leaf callbacks
prove the fixture's effects; production still leaves arbitrary results unverified.

The first run found an acknowledgement/closing-animation race. The next run
delivered the correct callbacks but exposed a weak test: “already closed” could
satisfy dismissal. The final suite requires the intended transition explicitly
and checks the previously visible menu surfaces, not only AXSelected.

[Evidence and native regression reports](native-menu-evidence.json) record the
actual outcomes. All 20 existing native model/control cases and all 14 native
text cases also passed on this build; the Swift suite passed 85 tests. Both test apps were closed afterward. No personal applications,
microphone, physical Option key or screenshots were used. Visual fallback is
disabled in the menu diagnostic so a missing target becomes a test failure.

## Reproduce

Close Local Voice first. These commands briefly focus a disposable AppKit window,
use the existing Accessibility grant, and attempt to restore the previous app.

```sh
sh voice/build.sh
sh voice/research/native/build-text-fixture.sh
python3 voice/research/native/run-text-check.py --menus
python3 voice/research/native/run-text-check.py --grounded
python3 voice/research/native/run-text-check.py
```

This verifies standard AppKit menu-bar and nested-menu behavior. Context menus,
other GUI frameworks, auto-hidden menu bars and third-party apps have not been
live-tested by this suite. Arbitrary menu-command outcomes, large control trees,
native semantic multistep planning and broader visual grounding remain work in
progress. This addition does not replace the required vision component.
