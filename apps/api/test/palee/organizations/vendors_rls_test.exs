defmodule Palee.Organizations.VendorsRLSTest do
  @moduledoc """
  TD-205: an account reads its own vendor row and a vendor reads all, but only
  a vendor or the operator scope (`app.vendor_grant`) may create, change or
  delete one. Before, a session scoped to a user could make that user a
  vendor, and a session without any scope could make anyone one. Runs as the
  non-bypass runtime role, the only connection that proves it.
  """
  use Palee.RLSCase, async: false

  setup %{conn: conn} do
    {vendor_s, vendor} = uuid()
    {member_s, member} = uuid()
    unique = System.unique_integer([:positive])

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    for {id, nick} <- [{vendor, "rls_vendor_#{unique}"}, {member, "rls_vendor_member_#{unique}"}] do
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
    end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])

    operator(conn, fn -> insert_vendor(conn, vendor) end)

    on_exit(fn ->
      {:ok, cleanup} =
        Palee.Repo.config()
        |> Keyword.take([:hostname, :port, :username, :password, :database])
        |> Postgrex.start_link()

      Postgrex.query!(cleanup, "DELETE FROM vendors WHERE user_id = ANY($1)", [[vendor, member]])
    end)

    %{vendor: vendor_s, member: member_s, member_bin: member}
  end

  test "a user-scoped session cannot make its own account a vendor", ctx do
    as_session(ctx.conn, ctx.member, nil, false, fn ->
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        insert_vendor(ctx.conn, ctx.member_bin)
      end
    end)
  end

  test "a session without any scope cannot create a vendor", ctx do
    as_session(ctx.conn, "", nil, false, fn ->
      assert_raise Postgrex.Error, ~r/row-level security/, fn ->
        insert_vendor(ctx.conn, ctx.member_bin)
      end
    end)
  end

  test "an account reads only its own row; a vendor reads and changes all", ctx do
    as_session(ctx.conn, ctx.member, nil, false, fn ->
      assert vendor_count(ctx.conn) == 0
    end)

    as_session(ctx.conn, ctx.vendor, nil, false, fn ->
      assert vendor_count(ctx.conn) >= 1
      insert_vendor(ctx.conn, ctx.member_bin)

      %{num_rows: 1} =
        Postgrex.query!(ctx.conn, "UPDATE vendors SET status = 'revoked' WHERE user_id = $1", [
          ctx.member_bin
        ])
    end)

    as_session(ctx.conn, ctx.member, nil, false, fn ->
      %{num_rows: changed} =
        Postgrex.query!(ctx.conn, "UPDATE vendors SET status = 'active' WHERE user_id = $1", [
          ctx.member_bin
        ])

      assert changed == 0
    end)
  end

  test "the operator scope grants a vendor without being one", ctx do
    as_session(ctx.conn, "", nil, false, fn ->
      operator(ctx.conn, fn -> insert_vendor(ctx.conn, ctx.member_bin) end)
    end)

    as_session(ctx.conn, ctx.member, nil, false, fn ->
      assert [["active"]] = own_status(ctx.conn, ctx.member_bin)
    end)
  end

  defp insert_vendor(conn, user_id) do
    Postgrex.query!(
      conn,
      """
      INSERT INTO vendors (id, user_id, status, inserted_at, updated_at)
      VALUES (gen_random_uuid(), $1, 'active', now(), now())
      ON CONFLICT (user_id) DO UPDATE SET status = 'active', updated_at = now()
      """,
      [user_id]
    )
  end

  defp operator(conn, fun) do
    Postgrex.query!(conn, "SELECT set_config('app.vendor_grant', 'true', false)", [])
    fun.()
  after
    Postgrex.query!(conn, "SELECT set_config('app.vendor_grant', '', false)", [])
  end

  defp own_status(conn, user_id) do
    Postgrex.query!(conn, "SELECT status FROM vendors WHERE user_id = $1", [user_id]).rows
  end

  defp vendor_count(conn) do
    %{rows: [[count]]} = Postgrex.query!(conn, "SELECT count(*)::int FROM vendors", [])
    count
  end
end
