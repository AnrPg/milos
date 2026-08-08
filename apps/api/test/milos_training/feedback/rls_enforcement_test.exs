defmodule MilosTraining.Feedback.RLSEnforcementTest do
  @moduledoc """
  Proves the reviews RLS policy actually isolates tenants. See
  MilosTraining.RLSCase for why an ordinary DataCase-based test can't do
  this (this suite runs as a Postgres superuser, which bypasses RLS).
  """
  use MilosTraining.RLSCase, async: false

  test "a review is invisible outside its own organization's session", %{conn: conn} do
    {org_id_s, org_id} = uuid()
    {other_org_id_s, other_org_id} = uuid()
    {user_id_s, user_id} = uuid()
    {review_id_s, review_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Feedback Org', $2, 'active', now(), now())
      """,
      [org_id, "rls-feedback-#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Feedback Other Org', $2, 'active', now(), now())
      """,
      [other_org_id, "rls-feedback-other-#{System.unique_integer([:positive])}"]
    )

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [user_id, "rls_feedback_user_#{System.unique_integer([:positive])}"]
    )

    as_session(conn, user_id_s, org_id_s, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO reviews (id, user_id, target_type, organization_id, inserted_at, updated_at)
        VALUES ($1, $2, 'workout', $3, now(), now())
        """,
        [review_id, user_id, org_id]
      )
    end)

    visible_in_own_org =
      as_session(conn, user_id_s, org_id_s, false, fn -> select_ids(conn, review_id) end)

    visible_in_other_org =
      as_session(conn, user_id_s, other_org_id_s, false, fn -> select_ids(conn, review_id) end)

    visible_with_no_context =
      as_session(conn, user_id_s, nil, false, fn -> select_ids(conn, review_id) end)

    assert visible_in_own_org == [review_id_s]
    assert visible_in_other_org == []
    assert visible_with_no_context == []

    as_session(conn, user_id_s, org_id_s, false, fn ->
      Postgrex.query!(conn, "DELETE FROM reviews WHERE id = $1", [review_id])
    end)

    Postgrex.query!(conn, "DELETE FROM organizations WHERE id = ANY($1)", [
      [org_id, other_org_id]
    ])

    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [user_id])
  end

  defp select_ids(conn, id) do
    %{rows: rows} = Postgrex.query!(conn, "SELECT id FROM reviews WHERE id = $1", [id])
    Enum.map(rows, fn [row_id] -> Ecto.UUID.load!(row_id) end)
  end
end
