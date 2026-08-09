defmodule MilosTraining.RLSCase do
  @moduledoc """
  For tests that must prove an RLS policy actually blocks something.

  This whole suite runs against Postgres as a superuser (rolbypassrls =
  true - see F-07 in the multi-tenancy audit), so ordinary Ecto-based tests
  never exercise Row Level Security: every query succeeds regardless of
  policy correctness, RED and GREEN alike. `use MilosTraining.RLSCase`
  self-provisions a dedicated non-superuser role and hands each test a raw
  `Postgrex` connection (`conn` in the test context) that genuinely enforces
  RLS, plus small helpers for setting the `app.*` session GUCs the policies
  read.

  This is scoped to genuinely RLS-relevant tests only - most tests should
  keep using `MilosTraining.DataCase`, which is faster and simpler because it
  doesn't need real tenant isolation to hold.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import MilosTraining.RLSCase, only: [as_session: 5, uuid: 0]
    end
  end

  @runtime_role "milos_test_runtime"
  @runtime_password "milos_test_runtime_pw"

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MilosTraining.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    # Provisioning the runtime role has to happen on a connection outside the
    # Ecto sandbox: `MilosTraining.Repo` runs every query inside a transaction
    # that's rolled back when the owner above stops, so CREATE ROLE/GRANT
    # issued through it never durably take effect. The separate `conn` this
    # test gets below is a genuinely different physical connection/role and
    # needs privileges that actually persisted.
    {:ok, admin_conn} =
      Postgrex.start_link(
        hostname: System.get_env("DB_HOST", "localhost"),
        port: String.to_integer(System.get_env("DB_PORT", "5432")),
        username: System.get_env("DB_USER", "postgres"),
        password: System.get_env("DB_PASSWORD", "postgres"),
        database:
          System.get_env("DB_NAME", "milos_training_test#{System.get_env("MIX_TEST_PARTITION")}")
      )

    Postgrex.query!(
      admin_conn,
      """
      DO $$ BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{@runtime_role}') THEN
          CREATE ROLE #{@runtime_role} LOGIN PASSWORD '#{@runtime_password}';
        END IF;
      END $$;
      """,
      []
    )

    Postgrex.query!(
      admin_conn,
      "ALTER ROLE #{@runtime_role} NOBYPASSRLS NOSUPERUSER",
      []
    )

    Postgrex.query!(
      admin_conn,
      "GRANT USAGE ON SCHEMA public TO #{@runtime_role}",
      []
    )

    Postgrex.query!(
      admin_conn,
      "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{@runtime_role}",
      []
    )

    Postgrex.query!(
      admin_conn,
      "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{@runtime_role}",
      []
    )

    GenServer.stop(admin_conn)

    {:ok, pid} =
      Postgrex.start_link(
        hostname: System.get_env("DB_HOST", "localhost"),
        port: String.to_integer(System.get_env("DB_PORT", "5432")),
        username: @runtime_role,
        password: @runtime_password,
        database:
          System.get_env("DB_NAME", "milos_training_test#{System.get_env("MIX_TEST_PARTITION")}")
      )

    # These tests write outside the Ecto sandbox (the raw connection is the whole
    # point), so nothing rolls back. Without this every run left its
    # organizations and users behind, which then skewed suite-wide count
    # assertions elsewhere. Cleanup lives here rather than in each test so it
    # also runs when a test fails partway through.
    on_exit(fn ->
      {:ok, cleanup} =
        Postgrex.start_link(
          hostname: System.get_env("DB_HOST", "localhost"),
          port: String.to_integer(System.get_env("DB_PORT", "5432")),
          username: System.get_env("DB_USER", "postgres"),
          password: System.get_env("DB_PASSWORD", "postgres"),
          database:
            System.get_env(
              "DB_NAME",
              "milos_training_test#{System.get_env("MIX_TEST_PARTITION")}"
            )
        )

      Postgrex.query!(
        cleanup,
        "DELETE FROM organization_memberships WHERE user_id IN (SELECT id FROM users WHERE nickname LIKE 'rls\_%')",
        []
      )

      Postgrex.query!(cleanup, "DELETE FROM users WHERE nickname LIKE 'rls\_%'", [])
      Postgrex.query!(cleanup, "DELETE FROM organizations WHERE slug LIKE 'rls-%'", [])

      GenServer.stop(cleanup)
    end)

    {:ok, conn: pid}
  end

  @doc "Generates a UUID as both its string form (for set_config/text params) and its 16-byte binary form (for uuid columns)."
  def uuid do
    s = Ecto.UUID.generate()
    {s, Ecto.UUID.dump!(s)}
  end

  @doc """
  Runs `fun` with the given `app.user_id` / `app.organization_id` /
  `app.admin_mode` session GUCs set on `conn`, matching what
  `RepoContext.run/2` sets for real request/job connections.
  """
  def as_session(conn, user_id_s, organization_id_s, admin_mode, fun) do
    Postgrex.query!(conn, "SELECT set_config('app.user_id', $1, false)", [user_id_s])

    Postgrex.query!(conn, "SELECT set_config('app.organization_id', $1, false)", [
      organization_id_s || ""
    ])

    Postgrex.query!(conn, "SELECT set_config('app.admin_mode', $1, false)", [
      if(admin_mode, do: "true", else: "")
    ])

    fun.()
  end
end
