# Named sections for repeated controls

Extension 0.4.6 can distinguish repeated control names using a named containing
section. This is a general DOM operation: no website-specific selector, model
call or additional permission is involved. Reload the unpacked extension after
updating its source.

Examples:

- `click Save button in the Profile section`
- `fill Email in the Billing form with local@example.test`
- `choose Canada from Country in Shipping section`
- `check Updates in Billing group`
- `copy Email in Profile section into Email in Billing section`
- `make Email in Billing section uppercase`

The final container word is required. A bare phrase such as `Save in Profile`
does not silently become a scope. Existing literal payloads remain literal;
`fill Message in Profile section with click Save in Billing section` only fills
the field. Ordinary names such as `Sign in` retain their existing behavior.

## How a section gets its name

| Spoken container | Observed structure |
| --- | --- |
| section, region, panel | HTML section or ARIA region |
| group | HTML fieldset or ARIA group |
| form | HTML form or ARIA form |
| dialog | HTML dialog or ARIA dialog |

An explicit `aria-labelledby` or `aria-label` supplies the name first. ID
references must resolve uniquely within that document or open shadow root.
Without an explicit label, one direct heading (or one heading in a direct
header) can name a container; a fieldset can use its legend. Several direct
headings do not imply a guessed name. Names match exactly after case, whitespace
and Unicode normalization, and are bounded to 100 characters.

The container must be available within the current interaction layer. A command
cannot escape an active modal. Duplicate container names or duplicate matching
controls inside the selected container stop before input. Hidden, disabled,
inert and unavailable controls retain their existing exclusions. Unnamed generic
divs, arbitrary cards, closed shadow roots and frames are not inferred as scopes.
The same scope can be named independently for the source and destination of an
existing-text operation.

A complete literal control label such as `Open in side panel` remains usable
when no matching named container exists. If both a literal full label and a
matching named container are present, the phrase is ambiguous and stops.

## Keep the same target through execution

Observation-bound clicks retain both the selected control and the actual
container identity. Before dispatch, the container must still match the request
and contain one matching available target. Renaming or replacing the container,
or introducing a second matching target, invalidates the selection.

Field edits also retain the container across focus callbacks. A page cannot move
the original field into a replacement same-named container, restore focus, and
receive the pending text. Verification checks the original scope again after
input; subsequent changes are unverified and never cause an automatic retry.
Existing-text operations bind both original container identities. No new success
criterion replaces the normal field-value, focus or control-transition checks.

## Evidence and limits

The generated headless suite passed 32/32 cases with independently read field
values, click/input counts and a no-submission check. It covers named regions,
headings, fieldset legends, forms, dialogs, open shadow roots, repeated labels,
literal/scope ambiguity, stale observations and focus/input-time replacement.
Before implementation, the original 27-case suite passed 12/27. Additional review
then exposed five failures, including replacement with focus and geometry
restored; those checks passed after binding container identity.

The [recorded results](tests/scoped-targets-evidence.json) include all 32 cases
and controller/test hashes. A Swift parser contract separately checks that seven
requests preserve their targets and literal payloads. These are authored offline
development fixtures, not a live-site generalization, speech or task-completion
benchmark. Timers use Chrome virtual time; reported durations are not latency
measurements. No personal browser, microphone or desktop input was used.

Run from the source checkout:

```sh
npm run test:scoped-targets
```

Scope discovery shares the existing bounded DOM traversal and cache. No extra
model is loaded. The end-to-end speed impact has not been measured live.
