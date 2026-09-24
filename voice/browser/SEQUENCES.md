# Verified browser sequences

In Chrome, two or three browser commands share one execution path whether the
rules or the local language model understand them. Exact commands do not call a
model. Examples:

- `click Details then fill Message with Hello`
- `click Filters then focus Reference number then type AB-123`
- `select Blue from Color then check Notifications`
- `click Details then copy text from Source to Heading`
- `click Details then fill Email in Billing form with hello@example.test`

The app checks the active extension’s sequence capability before sending input;
an older or cached dispatcher produces a reload message.

Each target is resolved when its step starts, from a new page observation. A
control revealed by the first step can therefore be the second step's target.
The result must be verified before the sequence proceeds. Inconclusive clicks,
changed documents, missing/ambiguous fields, lost focus and reverted edits stop
remaining steps. No action is replayed. A stopped sequence can have completed
its earlier steps; it is not a transaction and does not roll those actions back.

Exact activation, focus, named filling, typing after focus, selection, checkbox
state, scrolling, copying and case conversion are supported. Learned activation
and focus phrases use the existing local preflight and grounding models. All
unknown operations are checked before the first input. Exact named targets use
the DOM resolver and its scoped-name support; vision fallback is not part of this
sequence route. Searches, submission and tab changes should be separate utterances.
App-launch sequences keep their existing routing and early app activation.

Typing/filling consumes the remaining words literally. `focus Message then type
Hello, then click Send!` inserts that entire sentence; it does not click Send.
Mutating browser commands wait for the final transcript. Exact sequences also
work with `--no-grounded-commands`; unknown phrasing requires the local models.

## Evidence and limits

`npm run test:sequences` compiles a small offline adapter around the **same Swift
planner and executor used by the app**. It exchanges observations and commands
with the production controller in a separate headless Chrome profile. The 37
fixtures check actual field contents, text input counts, control event counts
and absence of submission, including post-action changes and dispatch races.
A delayed test-transport case ensures virtual time advances only after Chrome
acknowledges that the action started. Two routing cases use controlled model replies; this is not new model-accuracy
evidence. The original 33 cases use simulated page time; four offscreen cases
use actual rendering events, in a separate disposable browser. These checks are
behavior tests, not latency benchmarks. The offscreen cases cover focus then
typing, checking then returning to a field above, a scoped form revealed by a
previous step, and target replacement before dispatch.

The tests do not use speech, the personal browser, the native messaging transport,
or the app's hotkey interface. A fresh end-to-end voice check remains unmeasured.
See [recorded results](tests/sequences-evidence.json). Source builds need the app
rebuilt and extension 0.4.9 reloaded to receive this change. The v0.1 release
archives remain unchanged.
