# Control types on the fast browser path

Extension 0.4.8 uses the requested control type when resolving an exact browser
name. It supports button, link, checkbox, switch, radio/radio button, tab, option,
menu item, and editable-field terms. This applies to activation and text-entry targeting, including the
observations used by the app's exact click and sequence paths. No language-model
call or website-specific selector is needed.

Copy/case commands use their separately documented [strict field-name resolver](EXISTING-TEXT.md).

Examples:

- `click Notifications checkbox`
- `click the link called Notifications`
- `click Filters switch in Account section`
- `click Details menu item then focus Message field then type Hello`
- `click the tab named Account then fill Email in Account section with Hello`

The same label can belong to several control types. An explicit type filters the
choice; an unqualified duplicate still refuses. A literal observed control name
such as `Help link` keeps its meaning, including when a link named `Help` also
exists. Disabled literal names do not cause a click on the other interpretation.
A control with the exact requested name but the wrong type cannot be replaced
by a similarly named control of the requested type.

Named observations retain their query and scope. Before dispatch, the controller
rechecks the selected identity, role, name and unique interpretation. A new
literal name, duplicate target or changed input type invalidates an earlier
binding. Existing verification still decides whether the resulting effect is
known: delivering a click does not by itself establish success.

## Evidence

`npm run test:role-targets` uses generated pages in a disposable offline Chrome
profile. It checks actual click events and field focus after the app's exact
preflight pattern: observe a name, require one enabled clickable target, then
send an identity-bound action. It does not invoke a language model or personal
browser. The [source-bound record](tests/role-targets-evidence.json) passes 64/64
cases. This is target-selection evidence, not arbitrary-task or speech coverage.

The first 60-case run passed 34/60. Failures included unsupported type wording,
wrong literal-name interpretations and missing revalidation. After those fixes,
four additional review cases exposed two incorrect related-label clicks and two
abstentions. All four are retained in the final 64-case suite. Four new cases in
`npm run test:sequences` also exercise the production Swift planner/executor with
typed controls and the resulting field contents; the full sequence suite has
33 cases.

The resolver shares one visible-control pool between name interpretation and
matching. It keeps the existing scan and observation bounds. This does not prove
end-to-end voice latency; speech, transport and effect verification are separate
stages. The existing [learned role-language checks](ROLE-LANGUAGE.md) describe the
local-model route and its own limitations.

Reload the unpacked extension to use this source update. The v0.1 download
archives have not changed.
