defmodule Palee.Infrastructure.Tenancy.RepoContextTest do
  use Palee.DataCase, async: false

  alias Palee.Infrastructure.Tenancy.RepoContext

  test "run/2 sets app.execution_authorization_check for a context with no organization_id or user_id" do
    result =
      RepoContext.run(%{execution_authorization_check: true}, fn ->
        RepoContext.current_setting("app.execution_authorization_check")
      end)

    assert result == "true"
  end

  test "run/2 rejects a context with no organization_id, user_id, or execution_authorization_check" do
    assert RepoContext.run(%{}, fn -> :should_not_run end) ==
             {:error, :missing_ownership_scope}
  end

  test "nested runs restore the outer settings, on the connection and in the process" do
    outer_org = Ecto.UUID.generate()
    inner_org = Ecto.UUID.generate()
    user = Ecto.UUID.generate()

    seen =
      RepoContext.run(%{organization_id: outer_org, user_id: user}, fn ->
        inner =
          RepoContext.run(%{organization_id: inner_org, user_id: user}, fn ->
            {RepoContext.current_setting("app.organization_id"),
             connection_setting("app.organization_id")}
          end)

        {inner, RepoContext.current_setting("app.organization_id"),
         connection_setting("app.organization_id")}
      end)

    assert seen == {{inner_org, inner_org}, outer_org, outer_org}
    assert RepoContext.current_setting("app.organization_id") == nil
  end

  test "a value set on the connection before run/2 is restored afterwards" do
    org = Ecto.UUID.generate()
    Palee.Repo.query!("SELECT set_config('app.organization_id', $1, false)", [org])

    RepoContext.run(%{organization_id: Ecto.UUID.generate()}, fn -> :ok end)

    assert connection_setting("app.organization_id") == org
  end

  test "a nested run in the same scope costs no settings round trips" do
    context = %{organization_id: Ecto.UUID.generate(), user_id: Ecto.UUID.generate()}
    parent = self()
    handler = "repo-context-test-#{System.unique_integer()}"

    :telemetry.attach(
      handler,
      [:palee, :repo, :query],
      fn _event, _measurements, %{query: query}, _ ->
        send(parent, {:query, query})
      end,
      nil
    )

    RepoContext.run(context, fn ->
      flush_queries()
      RepoContext.run(context, fn -> RepoContext.current_setting("app.user_id") end)
      refute_received {:query, _query}
    end)

    :telemetry.detach(handler)
  end

  defp connection_setting(name) do
    %{rows: [[value]]} = Palee.Repo.query!("SELECT current_setting($1, true)", [name])
    value
  end

  defp flush_queries do
    receive do
      {:query, _query} -> flush_queries()
    after
      0 -> :ok
    end
  end
end
