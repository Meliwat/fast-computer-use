# Named controls outside the viewport

Extension 0.4.9 can reveal an explicitly named control by scrolling before
clicking/focusing, filling, selecting an option or setting a checked state.
The target must already exist in the accessible DOM with a readable name and
real layout. This uses the same resolver across sites, without a model call.

Examples:

- `click Preferences button`
- `fill Email in Billing form with hello@example.test`
- `select Blue from Color`
- `check Notifications then fill Message with Hello`
- `focus Message then type Hello`

Visible matches take priority. Only when no visible control matches the name
does a named observation inspect matching controls outside the window or inside
an auto/scroll panel. The same explicit-type, literal-name, duplicate and named
section rules apply. Unfiltered observations remain limited to visible controls.

Before scrolling, the controller checks the original document, observed target
identity, name, role, geometry, scope and the requested operation. It scrolls
once, waits for two rendering frames (within a 500 ms cap and the command's
remaining deadline), then checks the same element again. Its coordinates can
change from scrolling; its name, role, size, relationships and unique meaning
must still agree. Actual visibility and hit testing must pass before input.
The frame wait lets scroll handlers and their queued layout work run; a timer
alone does not guarantee a rendering update. See the HTML specification's
[rendering update order](https://html.spec.whatwg.org/multipage/webappapis.html#update-the-rendering).

Replacement, newly ambiguous names, overlays, a changed URL/document, foreground
loss or failure to render stop the requested action. There is no scroll retry or
alternate target. The page may remain scrolled when the action stops. Ordinary
visible commands use the existing fast path and do not wait for these frames.
Existing post-action verification still decides whether the result is known;
a click event alone does not establish success. A scoped field may move because
of its own edit, but its identity, meaning and value must still verify afterward.

## Limits

This is not a search through an unknown page or an arbitrary-goal planner.
Virtualized/unmounted controls, closed disclosures, hidden elements, fixed
controls positioned outside the viewport, frames, closed shadow roots and
canvas-only controls are not recovered by this path. Overflow-hidden/clip
containers are not scrolled to expose clipped content. Protected and disabled
controls are excluded from execution. The existing bounded DOM scan still
applies. Focused dictation, browser search preparation and copy/case commands
keep their existing targeting rules.

A native select's own offscreen position is supported; opening and traversing
custom menus still requires explicit actions with observable results. Text is
not submitted just because a field was revealed and filled. The app's separate
navigation preflight uses the named observation to preserve an offscreen link's
expected destination before dispatch.

## Evidence

`npm run test:offscreen` passes 49 authored cases in a disposable, offline Chrome
profile using actual rendering events. The tests check input/click counts,
values, focus and scroll position independently of the controller's response.
Mutation cases assert that their scroll handler actually ran, so a refused
action cannot pass merely because the mutation never happened. Coverage includes
vertical/horizontal/nested scrolling, open shadow roots, named forms, visible
priority, ambiguity, layout changes, occlusion and inaccessible targets. See the
[source-bound results](tests/offscreen-evidence.json).

`npm run test:sequences` passes 37 cases through the production Swift planner
and executor, including four new offscreen flows. Existing role, scope, widget,
text, disclosure and editor fixtures also pass. These are generated behavior
checks, not a real-site success rate, language-model evaluation, speech test or
end-to-end latency benchmark. The tests do not use a personal browser profile.

Build the app from current source and reload the unpacked extension to use both
parts of this change. Published v0.1 archives remain unchanged.
