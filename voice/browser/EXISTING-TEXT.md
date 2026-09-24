# Editing existing field text

Controller 15 / extension 0.4.5 adds local operations on text already present in
named fields. No model call or clipboard round trip is required.

Examples:

- `copy City into Heading`
- `copy the text from the First name field to the Nickname field`
- `make Description lowercase`
- `convert Title to uppercase`
- `uppercase the Title`

Copy replaces the destination's entire text with the source's current text.
Case changes operate on the current field value, including Unicode. Empty sources
intentionally clear their destination. These are plain-text operations; rich-text
formatting is not copied. Neither operation sends or submits the result.

The parser recognizes these bounded patterns and common polite prefixes. It does
not yet interpret arbitrary rewriting requests, pronouns, conditional edits or
conversational corrections. This addition expands useful actions across sites;
it does not incorporate the experimental goal planner.

## Field selection and verification

Both fields must be uniquely named and visible in the current interaction scope.
Labels are normalized, with optional “the” and field/input/editor wording. Related
names are not treated as synonyms on this path. Password, hidden, disabled and
ambiguous fields are excluded. A read-only source is permitted; the destination
must be writable. Source and resulting text are limited to 16,000 UTF-16 units.

The controller reads the source, computes the result, focuses the destination,
and rechecks both fields before issuing one edit. It verifies the resulting text
and context for 180 ms; a distinct source must remain unchanged. Browser editing
uses Chrome's editing engine and trusted input events. Native editing uses
Accessibility values. A changed field, focus loss or delayed reversion stops the
operation without repeating or undoing it. An edit may already have occurred
when its subsequent verification fails.

The app checks the running extension's existing-text capability before dispatch.
Reload the extension once after updating to 0.4.5, then relaunch Local Voice when
ready. Older dispatchers return an update message before input.

## Evidence and limits

All **28 authored real-Chrome checks passed** with the production controller in
an isolated offline browser. Eleven successful cases took **189–197 ms**, median
**193 ms**, including the 180 ms verification window. These timings exclude speech
recognition, native messaging and app startup. Independent field values, actual
application input handlers, trusted events, insertion-call counts and a real undo
check establish effects. The suite covers Unicode, multiline and rich-text fields,
read-only sources, ambiguity, protected fields, focus-time changes, delayed
reversion, source mutation and input sanitization. It makes no universal editor
compatibility claim. [Recorded results](tests/existing-text-evidence.json).

The first run reported 26/28 because multiline insertion generated three trusted
input events from a single insertion call. The final harness counts insertion
calls separately while retaining input events and value checks. An intervening
harness attempt stopped on a duplicate JavaScript binding; it produced no scored
report. The controller and expected final values were unchanged across these runs.

The Swift suite passes **90 tests**. Native field lookup and editing compile into
the app, but the new operations have **not yet had a live native execution check**.
An 18-case fixed diagnostic is ready in `research/native/run-text-check.py
--existing-text`; it requires the disposable foreground Text Fixture and existing
Accessibility permission. It was deliberately not launched during unattended work.
Earlier native fill/menu results do not establish this new operation's reliability.

Reproduce the browser check from the project root:

```sh
node voice/browser/tests/existing-text-headless.cjs --output existing-text-results.json
```

Existing editor, disclosure and widget checks also pass. No personal browser,
microphone, screen capture or desktop input was used for this change. No model
weights changed; the broader local planner remains a separate failed-promotion
experiment.
