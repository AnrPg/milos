defmodule MilosTraining.Infrastructure.Tenancy.RepoContextTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

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
end
