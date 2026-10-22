defmodule Palee.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Palee.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Palee.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Palee.DataCase
    end
  end

  setup tags do
    Palee.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Today in the test gym's zone (ADR-176/179): the day gym-local rules see.
  A subscription assigned "today" starts on it, so a test asserting dates
  against `Date.utc_today/0` breaks while the two differ (late UTC evening).
  """
  def gym_today,
    do:
      Palee.TimeZones.ZonedTime.local_date(
        DateTime.utc_now(),
        Palee.TimeZones.ZonedTime.default_zone()
      )

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Palee.Repo, shared: not tags[:async])
    allow_background_processes(pid)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if rls_enforced?(tags), do: enforce_rls!()
  end

  @doc """
  TD-046: the suite connects as a Postgres superuser (`rolbypassrls`), so
  Row Level Security never applies to ordinary tests and a query that skips
  `RepoContext.run/2` passes locally but returns nothing in production.

  Tests tagged `@moduletag :rls_enforced` (or every test when
  `PALEE_TEST_ENFORCE_RLS=1`) switch the sandbox transaction to the
  non-superuser `#{Palee.RLSCase.runtime_role()}` role with
  `SET LOCAL ROLE`, so RLS policies apply exactly as they do for the
  production runtime role. Use `bypass_rls/1` for fixture setup that models
  pre-existing data rather than the code under test.
  """
  def rls_enforced?(tags),
    do: Map.get(tags, :rls_enforced, false) or System.get_env("PALEE_TEST_ENFORCE_RLS") == "1"

  def enforce_rls! do
    Palee.Repo.query!("SET LOCAL ROLE #{Palee.RLSCase.runtime_role()}")
    :ok
  end

  @doc """
  Runs `fun` as the RLS-enforcing runtime role inside the sandbox transaction
  and restores the superuser test role afterwards, even if `fun` raises.
  """
  def with_runtime_role(fun) when is_function(fun, 0) do
    enforce_rls!()

    try do
      fun.()
    after
      Palee.Repo.query!("RESET ROLE")
    end
  end

  @session_settings ~w(
    app.organization_id
    app.user_id
    app.admin_mode
    app.execution_authorization_check
    app.invitation_redemption
    app.slug_alias_lookup
  )

  @doc """
  TD-092: runs `fun` with every RLS session setting (`app.*`) cleared, the way
  a production request or Oban job starts on a pooled connection, and restores
  the test's own settings afterwards.

  Tests often set `app.organization_id`/`app.user_id` on the sandbox
  connection for fixtures. Without this, a request issued afterwards inherited
  that ambient scope, so a code path missing `RepoContext.run/2` still passed.
  """
  def with_clean_session(fun) when is_function(fun, 0) do
    previous =
      Enum.map(@session_settings, fn name ->
        %{rows: [[value]]} =
          Palee.Repo.query!("SELECT current_setting($1, true)", [name])

        {name, value || ""}
      end)

    clear_session!()

    try do
      fun.()
    after
      Enum.each(previous, fn {name, value} -> set_session!(name, value) end)
    end
  end

  @doc "Clears every RLS session setting (`app.*`) on the sandbox connection."
  def clear_session! do
    Enum.each(@session_settings, &set_session!(&1, ""))
    :ok
  end

  defp set_session!(name, value),
    do: Palee.Repo.query!("SELECT set_config($1, $2, false)", [name, value])

  @doc """
  Runs `fun` as the superuser test role and restores the previous role.
  Only for fixtures: assertions about tenant isolation must run enforced.
  """
  def bypass_rls(fun) when is_function(fun, 0) do
    %{rows: [[role]]} = Palee.Repo.query!("SELECT current_user")

    if role == Palee.RLSCase.runtime_role() do
      Palee.Repo.query!("RESET ROLE")

      try do
        fun.()
      after
        Palee.Repo.query!("SET LOCAL ROLE #{role}")
      end
    else
      fun.()
    end
  end

  defp allow_background_processes(_owner_pid), do: :ok

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
