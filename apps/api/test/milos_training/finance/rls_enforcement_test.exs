defmodule MilosTraining.Finance.RLSEnforcementTest do
  @moduledoc """
  Proves the memberships RLS policy actually isolates tenants, closing the
  loop on F-04's fix (which removed the legacy-org COALESCE fallback). See
  MilosTraining.RLSCase for why an ordinary DataCase-based test can't do
  this (this suite runs as a Postgres superuser, which bypasses RLS).
  """
  use MilosTraining.RLSCase, async: false

  test "a membership is invisible outside its own organization's session", %{conn: conn} do
    {org_id_s, org_id} = uuid()
    {other_org_id_s, other_org_id} = uuid()
    {user_id_s, user_id} = uuid()
    {membership_id_s, membership_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Finance Org', $2, 'active', now(), now())
      """,
      [org_id, "rls-finance-#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Finance Other Org', $2, 'active', now(), now())
      """,
      [other_org_id, "rls-finance-other-#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [user_id, "rls_finance_user_#{System.unique_integer([:positive])}"]
    )

    as_session(conn, user_id_s, org_id_s, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO memberships
          (id, user_id, user_type_snapshot, status, signup_source, organization_id,
           inserted_at, updated_at)
        VALUES ($1, $2, 'member', 'active', 'direct', $3, now(), now())
        """,
        [membership_id, user_id, org_id]
      )
    end)

    visible_in_own_org =
      as_session(conn, user_id_s, org_id_s, false, fn -> select_ids(conn, membership_id) end)

    visible_in_other_org =
      as_session(conn, user_id_s, other_org_id_s, false, fn ->
        select_ids(conn, membership_id)
      end)

    visible_with_no_context =
      as_session(conn, user_id_s, nil, false, fn -> select_ids(conn, membership_id) end)

    assert visible_in_own_org == [membership_id_s]
    assert visible_in_other_org == []
    assert visible_with_no_context == []

    as_session(conn, user_id_s, org_id_s, false, fn ->
      Postgrex.query!(conn, "DELETE FROM memberships WHERE id = $1", [membership_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [
      [org_id, other_org_id]
    ])

    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [user_id])
  end

  defp select_ids(conn, id) do
    %{rows: rows} = Postgrex.query!(conn, "SELECT id FROM memberships WHERE id = $1", [id])
    Enum.map(rows, fn [row_id] -> Ecto.UUID.load!(row_id) end)
  end
end
