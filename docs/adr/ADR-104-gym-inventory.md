# ADR-104: Gym Inventory: Machines and Consumables
Date: 2026-10-12
Status: Accepted

## Context
Gyms own machines (rowers, bikes, treadmills) and appliances (washing
machine, fridge, air conditioning) that break and need servicing, and they
use up consumables (chalk, towels, cleaning products, paper) that run out.
Today this lives in staff memory or chat: nobody knows which machine is out
of order since when, who reported it, when it was last serviced, or how fast
chalk goes and what it costs. Coaches and janitors are the ones who notice;
owners, admins and front desk are the ones who fix and buy.

## Decision
- **New bounded context `Inventory`** with two tabs in one page:
  **Machines** (training machines and appliances, `category` `training` or
  `appliance`) and **Consumables**. Tables `inventory_machines`,
  `inventory_machine_events`, `inventory_supplies`,
  `inventory_supply_movements`, `inventory_supply_reports`, all tenant
  scoped with forced RLS and composite `(id, organization_id)` foreign keys.
- **Machine state follows its log** (`MachinePolicy`). Event kinds: `note`,
  `issue`, `out_of_order`, `repair_requested`, `maintenance`, `repaired`,
  `retired`. An issue makes the machine `needs_attention`; an issue with
  severity `safety` or `usable = false` and an `out_of_order` event make it
  `out_of_order`; maintenance or a repair returns it to `working` (and sets
  `last_serviced_on`); `retired` is final. The status is never edited
  directly. A machine may have a service interval; service is due when the
  interval since the last service (or purchase) has passed.
- **Notes have canonical fields plus free text.** Machine events carry
  `severity` (low, medium, high, safety), `symptom` (noise, not starting,
  broken part, leak, electrical, display, cleanliness, other), `usable` and a
  free-text `body`. "Running low" reports on consumables carry `level`
  (running low, empty), `seen_quantity`, `place` and a `note`. Every entry
  records who and when; a restock resolves the open reports of that item and
  records who resolved them (`resolved_at`, `resolved_by_id`).
- **Low stock is judged by days of stock left, not by count**
  (`StockPolicy`). Daily use is observed from the item's own `consume`
  movements in the last 180 days once there are at least 3 uses spread over
  at least 14 days; until then it comes from the item's consumption speed:
  fast ≈ 1 per day, regular ≈ 1 per week, slow ≈ 1 per 90 days. Status:
  `out` at zero, `critical` under 7 days left, `low` under 21 days, else
  `ok`. An optional reorder level raises the status to at least `low` when
  the count reaches it. The status is stored on the item after every
  movement.
- **Alerts only when the status worsens.** `ManageInventory` sends
  `inventory_stock_low` when a movement moves an item to a worse stock
  status, or when someone reports it running low, and
  `inventory_repair_needed` on `issue`, `out_of_order` and
  `repair_requested` events. Recipients are everyone with
  `manage_inventory` in the gym except the author.
- **Daily digest.** `InventoryDigestJob` runs at 07:07 UTC for every active
  gym and sends `inventory_digest` with counts (open reports, low and
  critical stock, service due or due within 7 days, machines not working,
  machine notes from the last day) and up to five item names, most urgent
  first. A day with nothing to report sends nothing.
- **Rights.** `manage_inventory` (owner, admin, front desk): add and edit
  items, prices, shops and links, record restocks, uses and recounts, log any
  machine event, archive, see the report. `report_inventory` (coach,
  janitor): see both lists without prices, shops, links, service contacts or
  serial numbers, add notes, issues and outages on machines, and report
  consumables running low. Repair calls, services, repairs and retiring stay
  with managers. Routes are mapped in `RouteCapabilities`.
- **Report.** For a period of 1 to 36 months (default 12): consumption and
  purchases per item, spend per item and per month (restock total, else
  quantity × unit price), and monthly inventory expenses as restocks plus
  costs logged on machine events (maintenance, repairs).
- Archiving hides a machine or consumable from the lists and keeps its log
  and movements for the report.

## Rationale
Deriving state from the log means the state always has a reason, an author
and a time, and the history doubles as the maintenance record. Canonical
fields make notes filterable and let the digest and alerts say what is wrong
without parsing text, while free text keeps room for detail. Days of stock
left is what decides whether to buy: two of something used once a year is
plenty, two of something used daily is not. Speed defaults give a sensible
answer from day one, and the observed rate takes over once there is enough
history. Alerting only on a worse status avoids a notification on every use.
Giving coaches and janitors a report-only right puts the people who notice
problems in the loop without exposing money.

## Alternatives Considered
- A fixed minimum count per item: rejected; it needs tuning per item and
  ignores how fast the item goes.
- Free-text notes only: rejected; not filterable or summarisable.
- Editing machine status directly: rejected; loses the reason and author.
- Alerting on every movement under a threshold: rejected as noisy; the
  digest covers ongoing state.
- One generic "asset" list for machines and consumables: rejected; machines
  have state and service, consumables have stock and spend.
- Putting inventory costs into Finance: deferred; the inventory report shows
  them and Finance stays about client money.

## Consequences
- Two new capabilities in `AccessPolicy` and the rights report; front desk
  gains inventory management.
- Three notification types (`inventory_repair_needed`,
  `inventory_stock_low`, `inventory_digest`) added through migration
  `20261014100100`, with push messages linking to the Inventory page.
- Consumption is only what staff record; nothing is consumed automatically
  by classes.
- Follow-ups are listed in TD-056.

## Implementation Notes
- Facade `Palee.Inventory`; pure rules in
  `Inventory.Domain.{MachinePolicy, StockPolicy, InventoryReport,
  InventoryDigest}`; port `InventoryStore` with
  `Infrastructure.Inventory.EctoInventoryStore`; alerts in
  `Application.ManageInventory`; job `Workers.InventoryDigestJob` (cron
  `7 7 * * *`, `analytics` queue).
- API under `/api/org/:slug/staff/inventory`: machines (list, create,
  update, archive, events), supplies (list, create, update, archive,
  movements, low reports) and `report`. `InventoryController` redacts money
  fields for callers without `manage_inventory`.
- A restock at a new unit price updates the item's price. Consumption cannot
  take stock below zero; a recount (`adjust`) sets the count.
- Quantity is set only on create; later changes go through movements so the
  history and the stock status stay consistent.
- Machines have an optional `location_id`, not yet used by the UI (TD-056).
