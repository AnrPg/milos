defmodule Mix.Tasks.Palee.Test.Migrate do
  @shortdoc "Creates and migrates the test database as a non-superuser owner role"

  @moduledoc """
  Prepares the test database the way production runs it: owned by a login
  role that is not a superuser (`milos_migrations` in prod, which has
  BYPASSRLS and nothing more), with the extensions installed beforehand by
  an administrator. The migrations run as that role, and the test suite
  connects as that role too (`Palee.Repo` in `config/test.exs`).

  A superuser may do things that the production roles may not, such as
  `CREATE FUNCTION ... SET <extension parameter>` (42501 in prod on
  2026-10-26), so a suite running as superuser hides that whole class of bug
  until the deploy.

  The admin credentials come from `:test_database_admin` (`DB_ADMIN_USER` /
  `DB_ADMIN_PASSWORD`, falling back to `DB_USER` / `DB_PASSWORD`, then
  `postgres`). They create the role and the database and install the
  extensions; nothing else runs as admin. A test database that an earlier
  run migrated as another role holds objects the owner role cannot alter, so
  it is dropped and created again once.

  `mix test` runs this task in place of `ecto.create` and `ecto.migrate`.

      mix palee.test.migrate [--quiet]
  """

  use Mix.Task

  # Production has these installed by the cluster administrator before any
  # migration runs; the migrations' own CREATE EXTENSION IF NOT EXISTS are
  # then no-ops, as they are here.
  @extensions ["pg_trgm", "postgis"]

  @impl Mix.Task
  def run(args) do
    unless Mix.env() == :test do
      Mix.raise("palee.test.migrate may drop the database; it only runs in MIX_ENV=test")
    end

    {opts, _, _} = OptionParser.parse(args, strict: [quiet: :boolean])
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    repo = Palee.Repo
    config = repo.config()
    admin = Application.fetch_env!(:palee, :test_database_admin)

    prepare_database!(config, admin)
    migrate!(repo, config, if(opts[:quiet], do: false, else: :info))
  end

  defp prepare_database!(config, admin) do
    owner = Keyword.fetch!(config, :username)
    database = Keyword.fetch!(config, :database)

    with_conn(config, admin, "postgres", fn conn ->
      Postgrex.query!(
        conn,
        """
        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{owner}') THEN
            CREATE ROLE #{owner} LOGIN;
          END IF;
        END $$
        """,
        []
      )

      Postgrex.query!(
        conn,
        "ALTER ROLE #{owner} LOGIN PASSWORD '#{config[:password]}' " <>
          "NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS",
        []
      )

      %{rows: rows} =
        Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [database])

      if rows == [] do
        Postgrex.query!(conn, ~s(CREATE DATABASE "#{database}" OWNER #{owner}), [])
      end
    end)

    if migrated_by_someone_else?(config, admin, owner) do
      with_conn(config, admin, "postgres", fn conn ->
        Postgrex.query!(conn, ~s{DROP DATABASE "#{database}" WITH (FORCE)}, [])
        Postgrex.query!(conn, ~s(CREATE DATABASE "#{database}" OWNER #{owner}), [])
      end)
    end

    with_conn(config, admin, "postgres", fn conn ->
      Postgrex.query!(conn, ~s(ALTER DATABASE "#{database}" OWNER TO #{owner}), [])
    end)

    with_conn(config, admin, database, fn conn ->
      # On Postgres 15+ `public` belongs to pg_database_owner; say it for 14.
      Postgrex.query!(conn, "GRANT ALL ON SCHEMA public TO #{owner}", [])

      Enum.each(@extensions, fn extension ->
        Postgrex.query!(conn, "CREATE EXTENSION IF NOT EXISTS #{extension}", [])
      end)
    end)
  end

  defp migrated_by_someone_else?(config, admin, owner) do
    with_conn(config, admin, config[:database], fn conn ->
      %{rows: rows} =
        Postgrex.query!(
          conn,
          """
          SELECT tableowner FROM pg_tables
          WHERE schemaname = 'public' AND tablename = 'schema_migrations'
          """,
          []
        )

      match?([[table_owner]] when table_owner != owner, rows)
    end)
  end

  # One migration per fresh pool, as a deploy runs its few pending
  # migrations in a new session: an earlier migration in the same session can
  # load an extension's library and so hide a privilege error (an unknown
  # extension parameter is only settable by a superuser until it loads).
  defp migrate!(repo, config, log) do
    Stream.repeatedly(fn -> migrate_one!(repo, config, log) end)
    |> Enum.find(&(&1 == []))
  end

  defp migrate_one!(repo, config, log) do
    {:ok, pid} =
      repo.start_link(
        name: nil,
        username: config[:username],
        password: config[:password],
        hostname: config[:hostname],
        port: config[:port],
        database: config[:database],
        pool: DBConnection.ConnectionPool,
        # The migrator holds one connection for its lock and runs on another.
        pool_size: 2,
        log: false
      )

    try do
      Ecto.Migrator.run(repo, :up, step: 1, dynamic_repo: pid, log: log)
    after
      Supervisor.stop(pid)
    end
  end

  defp with_conn(config, admin, database, fun) do
    {:ok, conn} =
      Postgrex.start_link(
        hostname: config[:hostname],
        port: config[:port],
        username: admin[:username],
        password: admin[:password],
        database: database
      )

    try do
      fun.(conn)
    after
      GenServer.stop(conn)
    end
  end
end
