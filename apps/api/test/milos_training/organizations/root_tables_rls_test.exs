defmodule MilosTraining.Organizations.RootTablesRLSTest do
  @moduledoc """
  F-16: the root tenant tables now carry RLS. Because the ordinary suite runs as
  a Postgres superuser, these policies are invisible to it - this is the only
  place they are actually exercised.

  Two things must both hold, and the second is the one that makes this risky:
  isolation between organizations, and the tenant-resolution path continuing to
  work. A policy that isolates perfectly but blocks login is an outage.
  """
  use MilosTraining.RLSCase, async: false

  setup %{conn: conn} do
    {member_a_s, member_a} = uuid()
    {member_b_s, member_b} = uuid()
    {org_a_s, org_a} = uuid()
    {org_b_s, org_b} = uuid()

    unique = System.unique_integer([:positive])

    # Seeded through the RLS connection itself: it lives outside the Ecto
    # sandbox, so anything written via Repo would be invisible to it. Writes
    # here run with no app.user_id set, which the policies' WITH CHECK would
    # refuse - so seeding happens before the policies can apply by using the
    # bootstrap carve-out.
    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

    for {id, nick} <- [{member_a, "rls_root_a_#{unique}"}, {member_b, "rls_root_b_#{unique}"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO users (id, nickname, display_nickname, password_hash, role, email, inserted_at, updated_at)
        VALUES ($1, $2::text, $2::text, 'x', 'member', $2::text || '@placeholder.invalid', now(), now())
        """,
        [id, nick]
      )
    end

    for {id, slug} <- [{org_a, "rls-root-a-#{unique}"}, {org_b, "rls-root-b-#{unique}"}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organizations (id, name, slug, status, inserted_at, updated_at)
        VALUES ($1, $2, $2, 'active', now(), now())
        """,
        [id, slug]
      )

      Postgrex.query!(
        conn,
        """
        INSERT INTO organization_settings (id, organization_id, timezone, default_locale, inserted_at, updated_at)
        VALUES ($1, $2, 'UTC', 'en', now(), now())
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), id]
      )
    end

    for {org_id, user_id} <- [{org_a, member_a}, {org_b, member_b}] do
      Postgrex.query!(
        conn,
        """
        INSERT INTO organization_memberships
          (id, organization_id, user_id, role, status, joined_at, inserted_at, updated_at)
        VALUES ($1, $2, $3, 'member', 'active', now(), now(), now())
        """,
        [Ecto.UUID.dump!(Ecto.UUID.generate()), org_id, user_id]
      )
    end

    Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])

    on_exit(fn ->
      # Same connection settings as seeding: outside the sandbox, so this must
      # clean up after itself rather than relying on rollback.
      {:ok, cleanup} =
        Postgrex.start_link(
          hostname: System.get_env("DB_HOST", "localhost"),
          port: String.to_integer(System.get_env("DB_PORT", "5432")),
          username: "postgres",
          password: "postgres",
          database:
            System.get_env(
              "DB_NAME",
              "milos_training_test#{System.get_env("MIX_TEST_PARTITION")}"
            )
        )

      for {table, column, ids} <- [
            {"organization_settings", "organization_id", [org_a, org_b]},
            {"organization_memberships", "organization_id", [org_a, org_b]},
            {"organizations", "id", [org_a, org_b]},
            {"users", "id", [member_a, member_b]}
          ] do
        Postgrex.query!(cleanup, "DELETE FROM #{table} WHERE #{column} = ANY($1)", [ids])
      end

      GenServer.stop(cleanup)
    end)

    {:ok,
     conn: conn,
     member_a_s: member_a_s,
     member_b_s: member_b_s,
     org_a_s: org_a_s,
     org_b_s: org_b_s}
  end

  test "tenant resolution still works: a member reads their own organization by slug", %{
    conn: conn,
    member_a_s: member_a_s,
    org_a_s: org_a_s
  } do
    # This is exactly what ResolveTenantContext does, under the user-scoped
    # session it now opens. If this returns nothing, login is broken.
    rows =
      as_session(conn, member_a_s, nil, false, fn ->
        %{rows: rows} =
          Postgrex.query!(conn, "SELECT id FROM organizations WHERE id = $1", [
            Ecto.UUID.dump!(org_a_s)
          ])

        rows
      end)

    assert length(rows) == 1
  end

  test "a member's own membership row is readable during resolution", %{
    conn: conn,
    member_a_s: member_a_s,
    org_a_s: org_a_s
  } do
    rows =
      as_session(conn, member_a_s, nil, false, fn ->
        %{rows: rows} =
          Postgrex.query!(
            conn,
            "SELECT id FROM organization_memberships WHERE organization_id = $1 AND user_id = $2",
            [Ecto.UUID.dump!(org_a_s), Ecto.UUID.dump!(member_a_s)]
          )

        rows
      end)

    assert length(rows) == 1
  end

  test "an organization is invisible to an account with no membership in it", %{
    conn: conn,
    member_a_s: member_a_s,
    org_b_s: org_b_s
  } do
    rows =
      as_session(conn, member_a_s, nil, false, fn ->
        %{rows: rows} =
          Postgrex.query!(conn, "SELECT id FROM organizations WHERE id = $1", [
            Ecto.UUID.dump!(org_b_s)
          ])

        rows
      end)

    assert rows == []
  end

  test "another organization's memberships and settings are invisible", %{
    conn: conn,
    member_a_s: member_a_s,
    org_b_s: org_b_s
  } do
    as_session(conn, member_a_s, nil, false, fn ->
      %{rows: memberships} =
        Postgrex.query!(
          conn,
          "SELECT id FROM organization_memberships WHERE organization_id = $1",
          [Ecto.UUID.dump!(org_b_s)]
        )

      %{rows: settings} =
        Postgrex.query!(conn, "SELECT id FROM organization_settings WHERE organization_id = $1", [
          Ecto.UUID.dump!(org_b_s)
        ])

      assert memberships == []
      assert settings == []
    end)
  end

  test "an ordinary member cannot see other members of their own organization", %{
    conn: conn,
    member_a_s: member_a_s,
    org_a_s: org_a_s
  } do
    # Only owners/admins see the whole roster; a plain member sees just their
    # own row, even inside their own organization.
    rows =
      as_session(conn, member_a_s, nil, false, fn ->
        %{rows: rows} =
          Postgrex.query!(
            conn,
            "SELECT user_id FROM organization_memberships WHERE organization_id = $1",
            [Ecto.UUID.dump!(org_a_s)]
          )

        rows
      end)

    assert Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end) == [member_a_s]
  end

  test "the invitation carve-out opens the organization to a not-yet-member", %{
    conn: conn,
    member_a_s: member_a_s,
    org_b_s: org_b_s
  } do
    rows =
      as_session(conn, member_a_s, nil, false, fn ->
        Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', 'true', false)", [])

        %{rows: rows} =
          Postgrex.query!(conn, "SELECT id FROM organizations WHERE id = $1", [
            Ecto.UUID.dump!(org_b_s)
          ])

        Postgrex.query!(conn, "SELECT set_config('app.invitation_redemption', '', false)", [])
        rows
      end)

    assert length(rows) == 1
  end

  test "with no acting user at all, nothing is visible", %{conn: conn, org_a_s: org_a_s} do
    rows =
      as_session(conn, "", nil, false, fn ->
        %{rows: rows} =
          Postgrex.query!(conn, "SELECT id FROM organizations WHERE id = $1", [
            Ecto.UUID.dump!(org_a_s)
          ])

        rows
      end)

    assert rows == []
  end
end
