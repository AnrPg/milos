# ADR-216: One join link per client role
Date: 2026-10-28
Status: Accepted

## Context
Settings › Πρόσβαση πελατών › Σύνδεσμος εγγραφής had one public link (`/join/<slug>`) with an either/or «Εγγράφεται ως» choice. A box has box members and athletes at the same time, so the owner had to flip the role back and forth, and every person holding the link joined with whatever role was set at that moment. ANR asked for either separate member and athlete links, both usable at any time, or one link where the person picks the role at sign-up, and leaned to separate links as safer for owners.

## Decision
- One link per client role, each switched on or off on its own; both can be on together.
  - Box members: `/join/<slug>`, the box's address, unchanged (QR codes already printed keep working, and members can still type the box's link in «Τα box και τα clubs μου»).
  - Athletes: `/join/<slug>/athlete/<key>`. The key is 72 random bits made when the link is first turned on. It survives off/on, and the owner can replace it («Νέος σύνδεσμος αθλητών»), which retires every copy of the old address.
- The visitor never chooses the role. The link they open sets it.
- Stored as `organization_settings.settings["join_link"] = %{"member" => %{"enabled"}, "athlete" => %{"enabled", "key"}}`. The earlier `%{"enabled", "role"}` carries over as the member link; an earlier athlete link had no key, so it reads as off.
- API: `GET/PUT /api/org/:slug/join-link` returns both links; PUT takes `{role, enabled?, rotate_key?}`. Public `GET /api/auth/join/:slug[/athlete/:key]` and `POST /api/memberships/join/:slug[/athlete/:key]`. A wrong key, a disabled link, an unknown slug and an inactive box all answer the same `404 join_link_unavailable`. Keys are compared in constant time.
- Joining never changes an existing membership's role (as before), and links only grant client roles.

## Rationale
With a role picker in the sign-up, anyone can make themselves an athlete, and the owner cannot hand out a link that means only one thing. With two links on the same guessable address (`/join/<slug>/athlete`), anyone holding the member link could work out the athlete one, so the athlete link needs a secret. The member link stays keyless because joining a box by its address is a feature.

## Alternatives Considered
- One link, the person picks the role at sign-up: simplest, but the owner loses control over who becomes an athlete.
- A key on both links: would break the box-address flow and printed QR codes for no gain, since the member link is meant to be public.

## Consequences
- The web settings tab is now «Σύνδεσμοι εγγραφής», with one card per link (switch, share box, and the new-key action on the athlete card).
- A box that had the old link set to athlete sees both links off and turns the athlete link on again to get its keyed address; the old `/join/<slug>` answers «not active» until then. Prod holds no real boxes yet, so no data migration was written.
