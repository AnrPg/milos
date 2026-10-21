defmodule Palee.Execution.TrainingLogRlsTest do
  @moduledoc """
  Proves the training_log_entries RLS policy (ADR-118) against a real
  non-superuser connection. See Palee.RLSCase.
  """
  use Palee.RLSCase, async: false

  defp insert_org(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Log Org', $2, 'active', now(), now())
      """,
      [id, "rls-log-org-#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp insert_user(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [id, "rls_log_#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp insert_entry(conn, org_id, user_id) do
    {entry_id_s, entry_id} = uuid()

    Postgrex.query(
      conn,
      """
      INSERT INTO training_log_entries
        (id, organization_id, user_id, source_type, title, performed_at_utc, idempotency_key,
         inserted_at, updated_at)
      VALUES ($1, $2, $3, 'freeform', 'Run', now(), $4, now(), now())
      """,
      [entry_id, org_id, user_id, "rls-#{System.unique_integer([:positive])}"]
    )
    |> case do
      {:ok, _result} -> {:ok, entry_id_s, entry_id}
      error -> error
    end
  end

  defp count_entry(conn, entry_id) do
    %{rows: [[count]]} =
      Postgrex.query!(conn, "SELECT count(*) FROM training_log_entries WHERE id = $1", [entry_id])

    count
  end

  test "owner writes inside the tenant; other tenants and users cannot read or forge rows",
       %{conn: conn} do
    {org_a_s, org_a} = insert_org(conn)
    {org_b_s, _org_b} = insert_org(conn)
    {owner_s, owner} = insert_user(conn)
    {other_s, _other} = insert_user(conn)

    {:ok, _entry_id_s, entry_id} =
      as_session(conn, owner_s, org_a_s, false, fn -> insert_entry(conn, org_a, owner) end)

    assert as_session(conn, owner_s, org_a_s, false, fn -> count_entry(conn, entry_id) end) == 1

    # Owner-only (no tenant) session: personal projections can read it.
    assert as_session(conn, owner_s, nil, false, fn -> count_entry(conn, entry_id) end) == 1

    # A different user acting in another tenant sees nothing.
    assert as_session(conn, other_s, org_b_s, false, fn -> count_entry(conn, entry_id) end) == 0

    # No session at all fails closed.
    assert as_session(conn, "", nil, false, fn -> count_entry(conn, entry_id) end) == 0

    # Writing a row for another user, or into another tenant, violates WITH CHECK.
    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             as_session(conn, other_s, org_a_s, false, fn -> insert_entry(conn, org_a, owner) end)

    assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
             as_session(conn, owner_s, org_b_s, false, fn -> insert_entry(conn, org_a, owner) end)

    Postgrex.query!(conn, "SELECT set_config('app.user_id', '', false)", [])
    Postgrex.query!(conn, "SELECT set_config('app.organization_id', '', false)", [])
  end
end
