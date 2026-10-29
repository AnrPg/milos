defmodule Palee.Execution.PlanSetsRlsTest do
  @moduledoc """
  ADR-270: the execution_plan_sets RLS policies against a real non-superuser
  connection (see Palee.RLSCase). Whoever can read the parent execution reads
  the actuals; only their owner writes or deletes them.
  """
  use Palee.RLSCase, async: false

  defp insert_org(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      """
      INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
      VALUES ($1, 'RLS Plan Sets Org', $2, 'active', now(), now())
      """,
      [id, "rls-plan-sets-org-#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp insert_user(conn) do
    {id_s, id} = uuid()

    Postgrex.query!(
      conn,
      """
      WITH login AS (
        INSERT INTO logins (id, email, password_hash, inserted_at, updated_at)
        VALUES (gen_random_uuid(), $2::text || '@placeholder.invalid', 'x', now(), now())
        RETURNING id
      )
      INSERT INTO users (id, nickname, display_nickname, role, login_id, inserted_at, updated_at)
      SELECT $1, $2::text, $2::text, 'member', login.id, now(), now() FROM login
      """,
      [id, "rls_plan_sets_#{System.unique_integer([:positive])}"]
    )

    {id_s, id}
  end

  defp insert_plan_set(conn, execution_id, user_id) do
    Postgrex.query(
      conn,
      """
      INSERT INTO execution_plan_sets
        (id, execution_id, user_id, section_id, row_id, block_index, round_index, inserted_at)
      VALUES (gen_random_uuid(), $1, $2, gen_random_uuid(), 'r1', 0, $3, now())
      """,
      [execution_id, user_id, System.unique_integer([:positive])]
    )
  end

  defp count(conn, execution_id) do
    %{rows: [[count]]} =
      Postgrex.query!(
        conn,
        "SELECT count(*) FROM execution_plan_sets WHERE execution_id = $1",
        [execution_id]
      )

    count
  end

  test "staff who read the execution read its actuals but cannot change or delete them",
       %{conn: conn} do
    {org_id_s, org_id} = insert_org(conn)
    {owner_id_s, owner_id} = insert_user(conn)
    {staff_id_s, staff_id} = insert_user(conn)
    {_execution_id_s, execution_id} = uuid()

    as_session(conn, owner_id_s, org_id_s, false, fn ->
      Postgrex.query!(
        conn,
        """
        INSERT INTO workout_executions
          (id, user_id, organization_id, source, status, started_at_utc, started_at_tz,
           inserted_at)
        VALUES ($1, $2, $3, 'self_selected', 'completed', now(), 'UTC', now())
        """,
        [execution_id, owner_id, org_id]
      )

      assert {:ok, _} = insert_plan_set(conn, execution_id, owner_id)
    end)

    as_session(conn, staff_id_s, org_id_s, false, fn ->
      # Reads through the parent execution.
      assert count(conn, execution_id) == 1

      assert %{num_rows: 0} =
               Postgrex.query!(
                 conn,
                 "DELETE FROM execution_plan_sets WHERE execution_id = $1",
                 [execution_id]
               )

      assert %{num_rows: 0} =
               Postgrex.query!(
                 conn,
                 "UPDATE execution_plan_sets SET actual_reps = 99 WHERE execution_id = $1",
                 [execution_id]
               )

      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               insert_plan_set(conn, execution_id, staff_id)

      assert {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} =
               insert_plan_set(conn, execution_id, owner_id)
    end)

    as_session(conn, owner_id_s, org_id_s, false, fn ->
      assert %{rows: [[nil]]} =
               Postgrex.query!(
                 conn,
                 "SELECT actual_reps FROM execution_plan_sets WHERE execution_id = $1",
                 [execution_id]
               )

      assert %{num_rows: 1} =
               Postgrex.query!(
                 conn,
                 "UPDATE execution_plan_sets SET actual_reps = 5 WHERE execution_id = $1",
                 [execution_id]
               )

      assert %{num_rows: 1} =
               Postgrex.query!(
                 conn,
                 "DELETE FROM execution_plan_sets WHERE execution_id = $1",
                 [execution_id]
               )

      Postgrex.query!(conn, "DELETE FROM workout_executions WHERE id = $1", [execution_id])
    end)
  end
end
