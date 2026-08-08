defmodule MilosTraining.Execution.RLSEnforcementTest do
  @moduledoc """
  Proves F-26's fix: ProcessWorkoutCompletionJob has no user_id/organization_id
  of its own to open a session with (it only has an execution_id), so it must
  rely on the app.execution_authorization_check GUC bypass clause on
  workout_executions' RLS policy. This proves that bypass clause actually
  works under real RLS enforcement (this suite runs as a Postgres superuser
  otherwise, which would mask the bug entirely - see MilosTraining.RLSCase).
  """
  use MilosTraining.RLSCase, async: false

  test "a workout execution is invisible to an unrelated session but visible with execution_authorization_check",
       %{conn: conn} do
    {owner_id_s, owner_id} = uuid()
    {other_id_s, _other_id} = uuid()
    {execution_id_s, execution_id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
      VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
      """,
      [owner_id, "rls_execution_user_#{System.unique_integer([:positive])}"]
    )

    as_session(conn, owner_id_s, nil, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO workout_executions
          (id, user_id, source, status, started_at_utc, started_at_tz, inserted_at)
        VALUES ($1, $2, 'self_selected', 'completed', now(), 'UTC', now())
        """,
        [execution_id, owner_id]
      )
    end)

    visible_to_unrelated_session =
      as_session(conn, other_id_s, nil, false, fn -> select_ids(conn, execution_id) end)

    visible_with_authorization_check =
      as_session(conn, other_id_s, nil, false, fn ->
        Postgrex.query!(
          conn,
          "SELECT set_config('app.execution_authorization_check', $1, false)",
          [
            "true"
          ]
        )

        select_ids(conn, execution_id)
      end)

    assert visible_to_unrelated_session == []
    assert visible_with_authorization_check == [execution_id_s]

    Postgrex.query!(conn, "SELECT set_config('app.execution_authorization_check', $1, false)", [
      ""
    ])

    as_session(conn, owner_id_s, nil, false, fn ->
      Postgrex.query!(conn, "DELETE FROM workout_executions WHERE id = $1", [execution_id])
    end)

    Postgrex.query!(conn, "DELETE FROM users WHERE id = $1", [owner_id])
  end

  defp select_ids(conn, id) do
    %{rows: rows} = Postgrex.query!(conn, "SELECT id FROM workout_executions WHERE id = $1", [id])
    Enum.map(rows, fn [row_id] -> Ecto.UUID.load!(row_id) end)
  end
end
