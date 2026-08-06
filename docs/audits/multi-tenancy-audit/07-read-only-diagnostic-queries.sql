-- Read-only diagnostic queries for the Milos Training multi-tenancy audit.
-- Every query here is SELECT-only. Run against a read-only connection or a
-- replica where possible. None of these were executed against production;
-- they were validated for syntax against the local dev schema during this
-- audit (see 08-test-gap-plan.md for the exact commands run).
--
-- DO NOT add DELETE/UPDATE/INSERT/ALTER/DROP/TRUNCATE statements to this file.

-- =============================================================================
-- 1. Confirm the runtime connection is not a superuser / cannot bypass RLS
--    before running anything else. If this returns rolsuper=t or
--    rolbypassrls=t, RLS provides no protection on this connection and every
--    query below will silently see all tenants' data.
-- =============================================================================
SELECT rolname, rolsuper, rolbypassrls
FROM pg_roles
WHERE rolname = current_user;

-- =============================================================================
-- 2. RLS enforcement inventory: every table vs relrowsecurity/relforcerowsecurity
--    and whether it has a legacy-organization COALESCE fallback baked into its
--    policy (finding F-05). Cross-check against
--    docs/architecture/tenant-ownership-inventory.md's full resource list —
--    any tenant-owned table absent from this result set has no RLS at all.
-- =============================================================================
SELECT
  c.relname AS table_name,
  c.relrowsecurity AS rls_enabled,
  c.relforcerowsecurity AS rls_forced,
  p.polname AS policy_name,
  pg_get_expr(p.polqual, p.polrelid) AS using_expression,
  pg_get_expr(p.polwithcheck, p.polrelid) AS with_check_expression,
  pg_get_expr(p.polqual, p.polrelid) ILIKE '%milos_legacy_organization_id%'
    OR pg_get_expr(p.polwithcheck, p.polrelid) ILIKE '%milos_legacy_organization_id%'
    AS has_legacy_fallback
FROM pg_class c
LEFT JOIN pg_policy p ON p.polrelid = c.oid
WHERE c.relkind = 'r'
  AND c.relnamespace = 'public'::regnamespace
ORDER BY has_legacy_fallback DESC NULLS LAST, table_name;

-- =============================================================================
-- 3. Tenant-owned tables with a NULL organization_id (unmapped rows).
--    Run per table from docs/architecture/tenant-ownership-inventory.md.
--    Interpretation: any non-zero count on a table classified Tenant-owned is
--    a backfill gap that must be closed before that table's RLS can be forced
--    without silently routing rows to the legacy org via the DEFAULT clause.
-- =============================================================================
-- Template (repeat per table):
-- SELECT count(*) AS unmapped_rows FROM <table> WHERE organization_id IS NULL;

SELECT 'class_types' AS table_name, count(*) AS unmapped_rows FROM class_types WHERE organization_id IS NULL
UNION ALL SELECT 'scheduling_settings', count(*) FROM scheduling_settings WHERE organization_id IS NULL
UNION ALL SELECT 'bookings', count(*) FROM bookings WHERE organization_id IS NULL
UNION ALL SELECT 'master_workouts', count(*) FROM master_workouts WHERE organization_id IS NULL
UNION ALL SELECT 'assigned_workouts', count(*) FROM assigned_workouts WHERE organization_id IS NULL
UNION ALL SELECT 'memberships', count(*) FROM memberships WHERE organization_id IS NULL
UNION ALL SELECT 'finance_invoices', count(*) FROM finance_invoices WHERE organization_id IS NULL
UNION ALL SELECT 'finance_settings', count(*) FROM finance_settings WHERE organization_id IS NULL
UNION ALL SELECT 'promotion_codes', count(*) FROM promotion_codes WHERE organization_id IS NULL
UNION ALL SELECT 'referral_programs', count(*) FROM referral_programs WHERE organization_id IS NULL
UNION ALL SELECT 'messaging_threads', count(*) FROM messaging_threads WHERE organization_id IS NULL
UNION ALL SELECT 'gamification_settings', count(*) FROM gamification_settings WHERE organization_id IS NULL
UNION ALL SELECT 'analytics_events', count(*) FROM analytics_events WHERE organization_id IS NULL
UNION ALL SELECT 'review_questionnaires', count(*) FROM review_questionnaires WHERE organization_id IS NULL
UNION ALL SELECT 'attendance_records', count(*) FROM attendance_records WHERE organization_id IS NULL;

-- =============================================================================
-- 4. Rows whose organization_id resolves to the legacy organization but whose
--    owning entity graph suggests they were created through a code path that
--    should have supplied an explicit tenant (e.g. finance settings, which
--    application code fetches via `limit: 1` with no predicate at all).
--    Interpretation: a nonzero count on finance_settings especially indicates
--    the singleton-settings pattern (finding F-06) is masking multi-tenant
--    settings rows that should not exist as a single global row.
-- =============================================================================
SELECT o.slug, count(*) AS finance_settings_rows
FROM finance_settings fs
JOIN organizations o ON o.id = fs.organization_id
GROUP BY o.slug
ORDER BY finance_settings_rows DESC;

-- =============================================================================
-- 5. Users table: confirm RLS status (finding: users RLS policy exists but was
--    never ENABLEd). Expect rls_enabled=false today; this query exists so the
--    same check can be re-run after remediation to confirm it flips to true.
-- =============================================================================
SELECT relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE oid = to_regclass('public.users');

-- =============================================================================
-- 6. Root tenant tables (organizations, organization_memberships,
--    organization_settings, organization_domains, registration_invitations)
--    RLS status. Expect all false today (no policies defined) — these are
--    intentionally platform-administered tables, but confirm no policy has
--    been silently added/removed since this audit.
-- =============================================================================
SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
WHERE c.relname IN (
  'organizations', 'organization_memberships', 'organization_settings',
  'organization_domains', 'registration_invitations', 'platform_owners'
)
AND c.relnamespace = 'public'::regnamespace;

-- =============================================================================
-- 7. Duplicate or orphaned organization memberships: a user with more than one
--    row for the same organization (would violate the intended
--    (organization_id, user_id) uniqueness invariant if a constraint were ever
--    dropped or bypassed by a migration).
-- =============================================================================
SELECT organization_id, user_id, count(*) AS membership_rows
FROM organization_memberships
GROUP BY organization_id, user_id
HAVING count(*) > 1;

-- =============================================================================
-- 8. Memberships referencing a user or organization that no longer exists
--    (orphaned foreign keys — should be impossible if FKs are enforced, but
--    confirms no NOT VALID / bypassed constraint is hiding orphans).
-- =============================================================================
SELECT om.id, om.organization_id, om.user_id
FROM organization_memberships om
LEFT JOIN organizations o ON o.id = om.organization_id
LEFT JOIN users u ON u.id = om.user_id
WHERE o.id IS NULL OR u.id IS NULL;

-- =============================================================================
-- 9. Users whose global `role` is `:admin` but who hold no `:owner`/`:admin`
--    organization membership anywhere — flags accounts where the legacy
--    global role may still be silently granting elevated access on code paths
--    that check `user.role` instead of membership role (finding F-02).
-- =============================================================================
SELECT u.id, u.nickname, u.role
FROM users u
WHERE u.role = 'admin'
  AND NOT EXISTS (
    SELECT 1 FROM organization_memberships om
    WHERE om.user_id = u.id AND om.role IN ('owner', 'admin') AND om.status = 'active'
  );

-- =============================================================================
-- 10. Registration invitations with invalid or suspicious scope: redeemed
--     invitations whose role exceeds what the issuer's own membership role
--     should have permitted at issuance time (requires joining issuer's
--     membership role at the time; this approximates by comparing current
--     issuer role, which may itself have changed since — treat as a lead, not
--     proof).
-- =============================================================================
SELECT
  ri.id AS invitation_id,
  ri.organization_id,
  ri.role AS granted_role,
  issuer_membership.role AS issuer_current_role,
  ri.issued_by_user_id,
  ri.redeemed_at
FROM registration_invitations ri
LEFT JOIN organization_memberships issuer_membership
  ON issuer_membership.organization_id = ri.organization_id
  AND issuer_membership.user_id = ri.issued_by_user_id
WHERE ri.redeemed_at IS NOT NULL
  AND ri.role = 'owner'
  AND (issuer_membership.role IS NULL OR issuer_membership.role NOT IN ('owner'));
-- Interpretation: any row returned is an invitation where a non-owner issuer
-- (per their *current* membership role) issued an :owner invitation — a
-- concrete instance of the privilege-escalation gap in finding F-07
-- (IssueInvitation not checking issuer-role >= granted-role).

-- =============================================================================
-- 11. Multiple active redemptions / replay: invitations with a redeemed_at set
--     more than once is impossible by schema (single column), but check for
--     multiple invitations sharing the same token_digest (should be unique).
-- =============================================================================
SELECT token_digest, count(*) AS rows_with_digest
FROM registration_invitations
GROUP BY token_digest
HAVING count(*) > 1;

-- =============================================================================
-- 12. Stale/expired unredeemed invitations still in "active" state — cleanup
--     candidates (informational; do not delete without the retirement plan's
--     approval gates).
-- =============================================================================
SELECT organization_id, role, expires_at, issued_by_user_id
FROM registration_invitations
WHERE redeemed_at IS NULL
  AND revoked_at IS NULL
  AND expires_at < now()
ORDER BY expires_at;

-- =============================================================================
-- 13. Cross-tenant foreign-key sanity check: assigned_workouts pointing at a
--     master_workout owned by a different organization than the assignment
--     itself. A nonzero count means a composite/same-tenant FK constraint is
--     missing or was bypassed.
-- =============================================================================
SELECT aw.id AS assigned_workout_id, aw.organization_id AS assignment_org,
       mw.organization_id AS workout_org
FROM assigned_workouts aw
JOIN master_workouts mw ON mw.id = aw.master_workout_id
WHERE aw.organization_id IS DISTINCT FROM mw.organization_id;

-- =============================================================================
-- 14. Same check for bookings -> scheduled_classes -> class_types chain.
-- =============================================================================
SELECT b.id AS booking_id, b.organization_id AS booking_org,
       sc.organization_id AS class_org
FROM bookings b
JOIN scheduled_classes sc ON sc.id = b.scheduled_class_id
WHERE b.organization_id IS DISTINCT FROM sc.organization_id;

-- =============================================================================
-- 15. Same check for finance_invoice_lines -> finance_invoices.
-- =============================================================================
SELECT fil.id AS line_id, fil.organization_id AS line_org,
       fi.organization_id AS invoice_org
FROM finance_invoice_lines fil
JOIN finance_invoices fi ON fi.id = fil.finance_invoice_id
WHERE fil.organization_id IS DISTINCT FROM fi.organization_id;

-- =============================================================================
-- 16. workout_executions rows whose organization_id (provenance) does not
--     correspond to any active membership of the execution's own user_id in
--     that organization — flags rows possibly created via the client-supplied
--     organization_id path in Execution.Commands.StartExecution (finding
--     F-03) for the self_selected/class_booking sources.
-- =============================================================================
SELECT we.id, we.user_id, we.organization_id, we.source
FROM workout_executions we
WHERE we.organization_id IS NOT NULL
  AND we.source IN ('self_selected', 'class_booking')
  AND NOT EXISTS (
    SELECT 1 FROM organization_memberships om
    WHERE om.user_id = we.user_id
      AND om.organization_id = we.organization_id
      AND om.status = 'active'
  );

-- =============================================================================
-- 17. Finance-provider identifiers linked to multiple tenants (if a
--     payment-provider customer/reference id column exists on
--     membership_payments or finance_invoices — adjust column name to the
--     actual provider-reference field once payment-provider integration
--     lands; currently the app is manual-payment-only per TD-001/TD-022, so
--     this is a forward-looking template).
-- =============================================================================
-- SELECT provider_customer_id, count(DISTINCT organization_id) AS tenant_count
-- FROM membership_payments
-- WHERE provider_customer_id IS NOT NULL
-- GROUP BY provider_customer_id
-- HAVING count(DISTINCT organization_id) > 1;

-- =============================================================================
-- 18. Suspended/archived organizations that still have rows created after
--     their lifecycle change timestamp (would indicate the suspended/archived
--     check is not actually blocking writes at every entry point).
-- =============================================================================
SELECT o.id, o.slug, o.status, ope.inserted_at AS lifecycle_change_at,
       (SELECT count(*) FROM bookings b
        WHERE b.organization_id = o.id AND b.inserted_at > ope.inserted_at) AS bookings_after_change
FROM organizations o
JOIN organization_provisioning_events ope
  ON ope.organization_id = o.id AND ope.event_type IN ('suspended', 'archived')
WHERE o.status IN ('suspended', 'archived');

-- =============================================================================
-- 19. Materialized views not covered by mix milos.tenancy.audit's table list:
--     confirm they are backed by explicit organization_id predicates in the
--     defining query (informational — re-run \d+ or pg_matviews after any
--     view redefinition).
-- =============================================================================
SELECT matviewname, definition
FROM pg_matviews
WHERE matviewname IN ('finance_aggregates', 'coaching_aggregates', 'weekly_leaderboard');

-- =============================================================================
-- 20. Deprecated/removed legacy table check: confirm assignment_messages
--     (marked "Removed legacy table" in the ownership inventory) is actually
--     gone, not just unused.
-- =============================================================================
SELECT to_regclass('public.assignment_messages') AS assignment_messages_table_oid;
-- Interpretation: NULL means the table is confirmed dropped.
