defmodule Palee.PersonalData.ExportRLSTest do
  @moduledoc """
  ADR-267: a "Download my data" request is the profile's own. Proves under
  real row-level security that another profile can neither see, change nor
  create one for it.
  """

  use Palee.RLSCase, async: false

  setup %{conn: conn} do
    unique = System.unique_integer([:positive])
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    people =
      for name <- [:owner, :stranger], into: %{} do
        {id_s, id} = uuid()
        nick = "rls_export_#{name}_#{unique}"

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
          [id, nick]
        )

        {name, {id_s, id}}
      end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])
    %{people: people}
  end

  defp insert(conn, user_id) do
    Postgrex.query!(
      conn,
      """
      INSERT INTO personal_data_exports (id, user_id, status, requested_at, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, 'pending', now(), now(), now())
      """,
      [user_id]
    )
  end

  defp count(conn),
    do: Postgrex.query!(conn, "SELECT count(*) FROM personal_data_exports", []).rows

  test "only the profile itself sees and changes its requests", %{conn: conn, people: people} do
    {owner_s, owner} = people.owner
    {stranger_s, _stranger} = people.stranger

    as_session(conn, owner_s, nil, false, fn ->
      insert(conn, owner)
      assert count(conn) == [[1]]
    end)

    as_session(conn, stranger_s, nil, false, fn ->
      assert count(conn) == [[0]]

      assert %{num_rows: 0} =
               Postgrex.query!(conn, "UPDATE personal_data_exports SET status = 'failed'", [])

      assert %{num_rows: 0} = Postgrex.query!(conn, "DELETE FROM personal_data_exports", [])

      assert_raise Postgrex.Error, ~r/row-level security/, fn -> insert(conn, owner) end
    end)

    as_session(conn, "", nil, false, fn ->
      assert count(conn) == [[0]]
    end)
  end
end
