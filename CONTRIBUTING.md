# Contributing

Small, reproducible improvements to command understanding, control targeting,
outcome verification and Mac installation are welcome. Keep the common command
path local and fast. Prefer capabilities that transfer across apps/sites.

## Report a problem

Open an issue with the app version, macOS version, chip, browser version, exact
spoken or typed command, target app/site, expected outcome, actual outcome and
the transcript-bar message. Indicate whether `doctor.py --verify-hashes` and
`doctor.py --browser-files` pass. Redact personal paths and content before sharing.
Do not include API keys, private recordings or sensitive screenshots.

## Development checks

From the repository root:

```sh
swift test --package-path voice
python3.11 -m unittest discover -s voice/Tests -p 'test_*.py'
npm ci --ignore-scripts
npm run test:browser
npm run test:outcomes
npm run test:aria
npm run test:existing-text
npm run test:scoped-targets
npm run test:role-targets
npm run test:offscreen
npm run test:sequences
npm run test:editor
python3.11 voice/browser/setup.py
python3.11 voice/browser/tests/test_native_host.py
```

Headless browser tests use a disposable profile and block external page requests.
They do not attach to your personal Chrome tabs. They require Chrome on macOS;
`VOICE_TEST_CHROME` can select another compatible Chrome executable.
Plain `setup.py` generates local host files; `--install` additionally registers
the host in your Chrome profile.

Add regression coverage for a real failure, document what a passing test proves,
and keep timing claims scoped to the measured stages. Do not enable speculative
model actions just because a model always returns valid JSON. Target selection
and post-action evidence must agree with the current UI state.

## Automated checks

Pull requests and updates to `main` run the source-export, Swift, packaging,
native-host and headless browser checks on a fresh GitHub-hosted macOS runner.
The workflow uses pinned actions, a read-only token and a 20-minute timeout.
It does not download model weights, sign a bundle, launch Local Voice, record
speech or request macOS permissions. A green run verifies these contracts and
fixtures; it is not a full installation or end-to-end voice test.

The workflow source lives in `voice/release/checks.yml` and is mirrored to
`.github/workflows/checks.yml` for source export. Keep both copies in sync.

## Source packaging

`voice/release/source-files.json` explicitly selects the published source. Update
it when adding files. Root README, changelog, contributor guide and package files
are mirrored from templates in `voice/release`; update both copies in this
standalone repository so a source export remains reproducible.

```sh
python3.11 voice/tools/export_source.py --check
python3.11 voice/tools/export_source.py --output /path/to/new-source.tar.gz
```

Do not commit recordings, traces, screenshots, model binaries, local runtime
configuration or credentials. Command weights are separate release assets;
upstream weights and dependencies keep their own licenses. This release contains
runtime source and tests, not the complete experimental training workspace.
