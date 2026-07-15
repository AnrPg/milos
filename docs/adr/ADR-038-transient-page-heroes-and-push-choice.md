# ADR-038: Transient Page Heroes and Per-Device Push Choice
Date: 2026-07-15
Status: Accepted

## Context
Large page heroes consume persistent vertical space throughout the application,
especially during repeat operational use. The dashboard also needs a clearer
control-panel visual hierarchy. Separately, browser push status currently mixes
server capability with a user's browser permission and device subscription.

## Decision
Application page heroes use a shared compact presentation that automatically
collapses after three seconds and can be restored with an accessible control.
The homepage hero is the sole persistent exception.

The admin dashboard uses the same transient hero behavior and presents suitable
KPIs as circular control-panel indicators without replacing exact metric values
with invented percentages.

Browser push is modeled as two independent gates: server VAPID capability and a
per-user, per-browser/device permission plus subscription. Capability is checked
fresh for every authenticated session and whenever the notification panel is
opened. Users explicitly enable or disable their current device.

## Rationale
Transient heroes preserve orientation on entry while returning space to the
task after a short delay. A shared component prevents timing, accessibility,
and motion behavior from drifting between roles and pages.

Separating server capability from device choice makes the UI truthful: users
cannot enable push when the server cannot send it, while a configured server
must not silently opt users or devices in.

## Alternatives Considered
Removing heroes entirely was rejected because they still provide useful page
orientation and primary context.

Persisting dismissal in local storage was rejected because the hero should be
available at the start of each page visit and should not become permanently
hidden.

Treating VAPID configuration as a user preference was rejected because it is a
server deployment capability. Automatically prompting for browser permission
was rejected because notification permission must remain an explicit user
choice.

## Consequences
Hero consumers must preserve a compact reveal control after collapse and honor
reduced-motion preferences. The homepage must not use the transient component.

The push hook exposes capability refresh separately from enable/disable actions.
The capability endpoint is non-cacheable, and stale browser subscriptions do
not override a disabled server state.

## Implementation Notes
`TransientHero` owns the three-second lifecycle and leaves an accessible
`Show intro` control after collapse. Operational admin and user pages use the
compact component; the public/home landing hero remains persistent. Calendar
controls that must remain usable are kept outside transient content.

The admin dashboard no longer exposes logout as an operational shortcut. Its
surface uses a subtle control-panel grid and circular KPI dials while preserving
exact textual values.

The push capability response sends `Cache-Control: no-store`. The client checks
capability during authenticated initialization and whenever the inbox opens.
Missing VAPID configuration is a capability state rather than a request error.
Admins receive deployment setup guidance; other users receive an administrator
handoff. Each browser can explicitly enable or disable its own subscription,
and denied permission guidance directs users to browser/site settings.
