defmodule MilosTraining.Scheduling.RLSEnforcementTest do
  @moduledoc """
  Proves the class_types RLS policy actually isolates tenants. See
  MilosTraining.RLSCase for why an ordinary DataCase-based test can't do
  this (this suite runs as a Postgres superuser, which bypasses RLS).
  """
  use MilosTraining.RLSCase, async: false

  test "a class_type is invisible outside its own organization's session", %{conn: conn} do
    {org_id_s, org_id} = uuid()
    {other_org_id_s, other_org_id} = uuid()
    {class_type_id_s, class_type_id} = uuid()

    Postgrex.query!(conn, """
    INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
    VALUES ($1, 'RLS Scheduling Org', $2, 'active', now(), now())
    """, [org_id, "rls-scheduling-#{System.unique_integer([:positive])}"])

    Postgrex.query!(conn, """
    INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
    VALUES ($1, 'RLS Scheduling Other Org', $2, 'active', now(), now())
    """, [other_org_id, "rls-scheduling-other-#{System.unique_integer([:positive])}"])

    as_session(conn, nil, org_id_s, false, fn ->
      Postgrex.query!(conn, """
      INSERT INTO class_types (id, name, slug, organization_id, inserted_at, updated_at)
      VALUES ($1, 'CrossFit', $2, $3, now(), now())
      """, [class_type_id, "crossfit-#{System.unique_integer([:positive])}", org_id])
    end)

    visible_in_own_org =
      as_session(conn, nil, org_id_s, false, fn -> select_ids(conn, class_type_id) end)

    visible_in_other_org =
      as_session(conn, nil, other_org_id_s, false, fn -> select_ids(conn, class_type_id) end)

    visible_with_no_context =
      as_session(conn, nil, nil, false, fn -> select_ids(conn, class_type_id) end)

    assert visible_in_own_org == [class_type_id_s]
    assert visible_in_other_org == []
    assert visible_with_no_context == []

    as_session(conn, nil, org_id_s, false, fn ->
      Postgrex.query!(conn, "DELETE FROM class_types WHERE id = $1", [class_type_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [
      [org_id, other_org_id]
    ])
  end

  defp select_ids(conn, id) do
    %{rows: rows} = Postgrex.query!(conn, "SELECT id FROM class_types WHERE id = $1", [id])
    Enum.map(rows, fn [row_id] -> Ecto.UUID.load!(row_id) end)
  end
end
