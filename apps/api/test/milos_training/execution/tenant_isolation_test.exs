defmodule MilosTraining.Execution.TenantIsolationTest do
  @moduledoc """
  Proves the workout_executions RLS policy blocks cross-tenant admin_mode
  reads. See MilosTraining.RLSCase for why this can't be an ordinary
  DataCase-based test.
  """
  use MilosTraining.RLSCase, async: false

  test "admin_mode bypass does not allow reading executions from an organization the admin is not a member of",
       %{conn: conn} do
    {org_id_s, org_id} = uuid()
    {owner_id_s, owner_id} = uuid()
    {admin_id_s, admin_id} = uuid()
    {execution_id_s, execution_id} = uuid()
    {_membership_id_s, membership_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Verify Org', $2, 'active', now(), now())
      """,
      [org_id, "rls-verify-org-#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [owner_id, "rls_owner_#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'admin', $2::text || '@placeholder.invalid', now(), now())
      """,
      [admin_id, "rls_admin_#{System.unique_integer([:positive])}"]
    )

    as_session(conn, owner_id_s, org_id_s, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO workout_executions
          (id, organization_id, user_id, source, status, started_at_utc, started_at_tz,
           current_segment_index, paused_elapsed_ms, total_elapsed_ms, section_elapsed_ms,
           segment_cycle_counts, checked_exercise_ids, section_scores, exercise_notes,
           exercise_modifications, lock_version, inserted_at)
        VALUES
          ($1, $2, $3, 'self_selected', 'active', now(), 'UTC',
           0, 0, 0, '{}', '{}', '{}', '{}', '{}', '{}', 1, now())
        """,
        [execution_id, org_id, owner_id]
      )
    end)

    rows_without_membership =
      as_session(conn, admin_id_s, nil, true, fn ->
        select_execution(conn, execution_id)
      end)

    assert rows_without_membership == [],
           "admin_mode bypass leaked an execution from an organization the admin is not a member of"

    # Seeded as a system path (no acting user), the way provisioning and
    # bootstrap create memberships. Inserting it while acting as an owner who
    # holds no membership themselves is not a flow the app has, and the root
    # tables' RLS now says so (F-16).
    Postgrex.query!(
      conn,
      """
      INSERT INTO organization_memberships
        (id, organization_id, user_id, role, status, joined_at, inserted_at, updated_at)
      VALUES ($1, $2, $3, 'coach', 'active', now(), now(), now())
      """,
      [membership_id, org_id, admin_id]
    )

    rows_with_membership =
      as_session(conn, admin_id_s, nil, true, fn ->
        select_execution(conn, execution_id)
      end)

    assert rows_with_membership == [execution_id_s],
           "admin_mode was over-corrected: a coach/admin with an active membership in the target org should still be able to read it"

    as_session(conn, owner_id_s, org_id_s, false, fn ->
      Postgrex.query!(conn, "DELETE FROM workout_executions WHERE id = $1", [execution_id])

      Postgrex.query!(conn, "DELETE FROM organization_memberships WHERE id = $1", [
        membership_id
      ])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = $1", [org_id])
    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [owner_id])
    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [admin_id])
  end

  defp select_execution(conn, execution_id) do
    %{rows: rows} =
      Postgrex.query!(conn, "SELECT id FROM workout_executions WHERE id = $1", [
        execution_id
      ])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end
end
