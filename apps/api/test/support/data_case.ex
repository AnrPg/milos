defmodule MilosTraining.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MilosTraining.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias MilosTraining.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import MilosTraining.DataCase
    end
  end

  setup tags do
    MilosTraining.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MilosTraining.Repo, shared: not tags[:async])
    allow_background_processes(pid)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    if rls_enforced?(tags), do: enforce_rls!()
  end

  @doc """
  TD-046: the suite connects as a Postgres superuser (`rolbypassrls`), so
  Row Level Security never applies to ordinary tests and a query that skips
  `RepoContext.run/2` passes locally but returns nothing in production.

  Tests tagged `@moduletag :rls_enforced` (or every test when
  `MILOS_TEST_ENFORCE_RLS=1`) switch the sandbox transaction to the
  non-superuser `#{MilosTraining.RLSCase.runtime_role()}` role with
  `SET LOCAL ROLE`, so RLS policies apply exactly as they do for the
  production runtime role. Use `bypass_rls/1` for fixture setup that models
  pre-existing data rather than the code under test.
  """
  def rls_enforced?(tags),
    do: Map.get(tags, :rls_enforced, false) or System.get_env("MILOS_TEST_ENFORCE_RLS") == "1"

  def enforce_rls! do
    MilosTraining.Repo.query!("SET LOCAL ROLE #{MilosTraining.RLSCase.runtime_role()}")
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
      MilosTraining.Repo.query!("RESET ROLE")
    end
  end

  @doc """
  Runs `fun` as the superuser test role and restores the previous role.
  Only for fixtures: assertions about tenant isolation must run enforced.
  """
  def bypass_rls(fun) when is_function(fun, 0) do
    %{rows: [[role]]} = MilosTraining.Repo.query!("SELECT current_user")

    if role == MilosTraining.RLSCase.runtime_role() do
      MilosTraining.Repo.query!("RESET ROLE")

      try do
        fun.()
      after
        MilosTraining.Repo.query!("SET LOCAL ROLE #{role}")
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
