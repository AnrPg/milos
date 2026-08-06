defmodule MilosTraining.Analytics.RLSEnforcementTest do
  @moduledoc """
  Proves the analytics_events RLS policy actually isolates tenants. See
  MilosTraining.RLSCase for why an ordinary DataCase-based test can't do
  this (this suite runs as a Postgres superuser, which bypasses RLS).
  """
  use MilosTraining.RLSCase, async: false

  test "an analytics event is invisible outside its own organization's session", %{conn: conn} do
    {org_id_s, org_id} = uuid()
    {other_org_id_s, other_org_id} = uuid()
    {event_id_s, event_id} = uuid()

    Postgrex.query!(conn, """
    INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
    VALUES ($1, 'RLS Analytics Org', $2, 'active', now(), now())
    """, [org_id, "rls-analytics-#{System.unique_integer([:positive])}"])

    Postgrex.query!(conn, """
    INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
    VALUES ($1, 'RLS Analytics Other Org', $2, 'active', now(), now())
    """, [other_org_id, "rls-analytics-other-#{System.unique_integer([:positive])}"])

    as_session(conn, nil, org_id_s, false, fn ->
      Postgrex.query!(conn, """
      INSERT INTO analytics_events (id, event_name, occurred_at, organization_id)
      VALUES ($1, 'rls_verify_event', now(), $2)
      """, [event_id, org_id])
    end)

    visible_in_own_org =
      as_session(conn, nil, org_id_s, false, fn -> select_ids(conn, event_id) end)

    visible_in_other_org =
      as_session(conn, nil, other_org_id_s, false, fn -> select_ids(conn, event_id) end)

    visible_with_no_context =
      as_session(conn, nil, nil, false, fn -> select_ids(conn, event_id) end)

    assert visible_in_own_org == [event_id_s]
    assert visible_in_other_org == []
    assert visible_with_no_context == []

    as_session(conn, nil, org_id_s, false, fn ->
      Postgrex.query!(conn, "DELETE FROM analytics_events WHERE id = $1", [event_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [
      [org_id, other_org_id]
    ])
  end

  defp select_ids(conn, id) do
    %{rows: rows} = Postgrex.query!(conn, "SELECT id FROM analytics_events WHERE id = $1", [id])
    Enum.map(rows, fn [row_id] -> Ecto.UUID.load!(row_id) end)
  end
end
