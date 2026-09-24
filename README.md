# Fast Computer Use

Local voice control for your Mac. The macOS app is called **Local Voice**.

Hold Option, speak a command, and release. A slim top bar shows the transcript
and result. The app uses on-device Apple speech recognition, small local command
models, Chrome DOM/macOS Accessibility, OCR and a resident GoClick vision model.
Actions execute by default. No API credential is needed for the normal local path.

**v0.1.0 · developer preview · Apple Silicon.** Build from source using the
[release assets](https://github.com/Meliwat/fast-computer-use/releases/tag/v0.1.0).
There is no drag-and-drop installer yet. The code is [MIT licensed](LICENSE);
upstream software and model assets retain their own licenses and notices.

This first release handles supported command types, generic UI controls and
short verified browser sequences. Arbitrary multi-step goals and experimental
model fine-tunes are not integrated. See the [release notes](CHANGELOG.md).

## Supported commands

| Say | Scope |
| --- | --- |
| `open Notes` / `open Codex` / `go to example.com` | Launch an app or website. |
| `open Codex then start a new chat` | Request its supported new-chat screen. |
| `fill Destination with Oslo` / `focus City` | Uniquely named browser/native fields. |
| `type hello there` | Literal insertion into the focused editor; Chrome can also find one unambiguous composer. |
| `search this site for local AI` / `scroll down` | Current Chrome page. |
| `choose Canada from the Country dropdown` | An observed browser option. |
| `click Save in Profile section` / `fill Email in Billing form with me@example.test` | Named browser sections disambiguate repeated controls. |
| `click Notifications link` / `check Email updates` | Observed controls, with role and state checks. |
| `open File menu` / `close menu` | Focused native app's menus. |
| `show the tools menu, then open Playground` | A supported short browser sequence with new observations between steps. |

These commands can transfer across sites/apps that expose compatible controls;
they still require supported request patterns and identifiable targets. Frames,
closed shadow roots, canvas controls, unnamed icons and arbitrary long goals
remain gaps. The X demo also has a narrow adapter for search-result verification.
Generic search submission does not establish that the results match the request.

## Existing text operations

`copy City into Heading` and `make Description lowercase` operate on the current
contents of named fields without a model call. Browser tests cover 28 cases;
native execution of these new operations still awaits a live fixture check. See
[behavior and measured scope](voice/browser/EXISTING-TEXT.md). Reload the extension
to 0.4.6 when updating.

Named section, form, group and dialog targeting is available on current main;
see [scope behavior and fixtures](voice/browser/SCOPED-TARGETS.md). These post-release
improvements are not part of the immutable v0.1.0 source archive.

## Build requirements

- Apple Silicon Mac, macOS 14 or newer, and Xcode command-line tools with Swift 6.
- Native Apple Silicon Python 3.11 and Python 3.12.
- A certificate-backed code-signing identity. The build discovers an Apple
  Development identity first, then a Developer ID Application identity, or accepts
  `VOICE_SIGN_IDENTITY`. If none is selected, it stops before compilation or model
  staging. A stable identity helps preserve macOS permission grants between rebuilds.
- The matching command-model archive, supplied separately. It is approximately
  49 MB; setup also downloads approximately 1.09 GB of pinned GoClick assets.
- Chrome for browser control. Node 22.13 or newer is needed only for browser tests.

Download `local-voice-source-v0.1.0.tar.gz` and
`local-voice-command-models-2026-09-23.tar.gz` from the release page. Keep the
source directory in a permanent location: Chrome's unpacked extension uses it.
The release also includes `SHA256SUMS` for checking the downloaded archives.
The command-model archive's SHA-256 is:

```text
f9c8d2642790f5e0359411c998c3ef10de13b35343a60dcb1c0c7cf018281f4b
```

Model revisions, filenames, sizes and hashes are pinned in
[models.lock.json](voice/models/models.lock.json). The installer validates these
assets before using them. Model weights are not included in this source archive.

## Install and launch

Extract the source archive, then run these commands from its
`local-voice-source` directory. Replace the model archive path with your download:

```sh
python3.11 voice/tools/install_runtime.py --commands /path/to/local-voice-command-models-2026-09-23.tar.gz
sh voice/build.sh
python3.11 voice/tools/doctor.py --verify-hashes --smoke
python3.11 voice/browser/setup.py --install
open 'voice/dist/Local Voice.app'
```

The installer uses isolated Python environments and model storage under
`~/Library/Application Support/LocalVoice/Runtime`. Dependencies can download
during installation; inference stays local and offline. All three command
checkpoints and the original GoClick weights are copied into the signed app.
Python remains external, so moving only the `.app` to another Mac is insufficient.
Install/build/doctor do not open apps, use the microphone or capture the screen.

For Chrome, open its Extensions page, enable Developer mode, choose Load unpacked,
and select `voice/browser/extension`. Allow access to HTTP/HTTPS sites once.
Commands then work on ordinary sites without per-site toolbar activation.
Keep the unpacked extension directory in place; reload it after updating.

If browser commands do nothing, run `python3.11 voice/tools/doctor.py --browser-files`.
It checks the registered host, extension ID, installed host code and interpreter
path without starting Chrome or sending input. A stale installation includes a
repair instruction. Passing these checks confirms files only; Chrome must still
have the extension enabled with site access, and Local Voice needs its macOS grants.

macOS requires Microphone, Speech Recognition and Accessibility grants for voice
control. Vision also requires Screen Recording: use **Allow visual screen access…**
in the app's waveform menu, then follow any macOS restart instruction. Permission
denial is not an installation failure. The app cannot grant these permissions.

Try `open Notes`, `open example.com`, or a command naming a visible control such
as `click Search`. `fill Destination with Oslo` works with a uniquely named
browser or native field; `type hello there` uses the focused editor. Native
filling recognizes labels, placeholders and linked captions, and verifies that
the value persists. In Chrome, `scroll down` uses the current page. Typing and
filling do not submit. See [native field support and its live test](voice/research/native/NATIVE-TEXT.md).
Native windows also support `focus City` and, with visible controls, phrases such
as `bring up Preferences` or `let me type into Subject`. The local model binds
its selection to actual Accessibility elements and rechecks the current window
before acting. See [native model integration and limits](voice/research/native/NATIVE-GROUNDING.md).
Native menu commands include `open File menu`, `click Save as`, and `close menu`.
Visible submenus use the same route; window controls are excluded while a menu
is open. [Menu support and limits](voice/research/native/NATIVE-MENUS.md) describe
what is verified. Closing a menu does not verify its command’s application result.
Unknown or ambiguous requests may stop. A delivered action is not always a
verified outcome. The original vision model is included; rejected experimental
fine-tunes are not installed.
The visual fallback can combine [wrapped visible labels](voice/vision/MULTILINE-TEXT.md)
inside one unnamed control when OCR confidence and geometric ownership agree.

To stop a command or quit, use the waveform menu in the macOS menu bar. Releasing
Option ends recording; it does not cancel an action already queued.

## Local processing

Speech requires Apple's on-device recognition; commands and visual observations
are processed locally. There is no paid API on the default path. Installation
downloads dependencies and model assets, and browser commands can of course
navigate to online services. A legacy opt-in Jev integration remains in the
source, disabled by default. It sends command text only if explicitly enabled
with an API key.

The app can read visible controls and, with Screen Recording permission, pixels
needed for visual targeting. Review commands before speaking: actions execute
automatically. Typing/filling alone does not submit a draft.

Browser details sections, pressed toggles, native popovers and explicitly linked
panels now support verified transitions. This lets a short command sequence
continue to a newly revealed control. Changes must persist for 120 ms within a
500 ms observation budget. Unrelated mutations, contradictory state and replaced
targets do not establish success. See [browser outcome checks](voice/browser/OUTCOMES.md).

Standard browser widgets also support named activation: switches, checkboxes,
radio buttons, listbox options, menu items and custom links. Existing local
semantic aliases can select these observed controls. Toggle/selection state is
verified when exposed; a plain click without a measurable outcome remains
unverified. See [widget support and limits](voice/browser/ARIA-WIDGETS.md).
Explicit types such as `click Notifications link` and `click Notifications
checkbox` distinguish matching labels. Literal names such as `Help link` remain
names. See [type-aware selection and evidence](voice/browser/ROLE-LANGUAGE.md).

## Offline checks

```sh
swift test --package-path voice
python3.11 -m unittest discover -s voice/Tests -p 'test_*.py'
npm ci --ignore-scripts
npm run test:browser
npm run test:outcomes
npm run test:aria
npm run test:existing-text
npm run test:scoped-targets
python3.11 voice/browser/setup.py
python3.11 voice/browser/tests/test_native_host.py
```

The plain browser setup command creates files in the source checkout; only
`--install` registers a host with Chrome. The transport test uses a temporary
home and simulated Chrome messages. `npm run test:editor` additionally starts a
separate headless Chrome with a temporary profile and blocked page networking;
it does not attach to personal tabs. `doctor.py --smoke` checks all three real
workers using synthetic inputs, without microphone, screenshots or UI input.
Its optional `--browser-files` check does not connect to Chrome, execute the native
host, or verify enabled-extension state or permissions.

Browser/model tests use authored fixtures and measure specific operations.
Their timings exclude speech unless explicitly stated. Tests and one-machine
installation checks do not establish clean-Mac onboarding,
permission continuity, broad visual accuracy or end-to-end voice latency.

## Source layout and release status

- `voice/Sources`: Swift app, command types, screenshot/OCR and model worker bridge.
- `voice/parser`, `voice/research/grounded`: production Python command workers.
  The grounded worker retains its historical directory name.
- `voice/vision`: local GoClick worker and contract tests.
- `voice/browser`: extension, native host, setup and disposable fixtures.
- `voice/tools`, `voice/runtime`, `voice/models`: installation, packaging and pins.
- `voice/Tests`: Swift and Python tests.
- `voice/licenses`: model notices, dependency inventory, and notice-review evidence.

Experimental training data, screenshots, personal traces, local configuration,
credentials, built apps and the older Paint demo are excluded. This snapshot
contains the runtime source and tests; it is not a complete training-data release.
`EXPORT-MANIFEST.json` records every included source file's hash and size.

The source includes tools to reproduce a separate dependency-notice archive;
see [dependency review](voice/licenses/DEPENDENCY-REVIEW.md). It preserves detected
installed notices and supplemental upstream licenses, and does not replace a
complete review of embedded libraries or change their licenses.

## Known limits and next steps

- Tested on one M1 Pro Mac with 16 GB RAM; a clean second-Mac install is unverified.
- Source installation requires a code-signing certificate and two Python versions.
  A self-contained, signed and notarized installer is future work.
- Visual targeting is conservative and requires Screen Recording permission.
  Unnamed icons, canvases and broad visual understanding remain limited.
- Native copy/case operations are implemented, but their live fixture check is pending.
- General language understanding and outcome verification need more coverage.
  There is no measured end-to-end speech latency distribution yet.
- Full native-library notice review is required before distributing a bundled
  Python runtime. This release distributes source and command weights separately.

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and useful bug reports. Please
report the exact command, target app/site, expected result and transcript-bar
message; omit private page content, audio and credentials.
