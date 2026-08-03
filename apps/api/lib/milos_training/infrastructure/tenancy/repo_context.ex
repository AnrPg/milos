defmodule MilosTraining.Infrastructure.Tenancy.RepoContext do
  alias MilosTraining.Repo

  def run(%{organization_id: organization_id} = context, fun)
      when is_binary(organization_id) and is_function(fun, 0) do
    Repo.transaction(fn ->
      set_local("app.organization_id", organization_id)
      maybe_set_user(context)
      fun.()
    end)
    |> unwrap_transaction()
  end

  def run(%{user_id: user_id}, fun) when is_binary(user_id) and is_function(fun, 0) do
    Repo.transaction(fn ->
      set_local("app.user_id", user_id)
      fun.()
    end)
    |> unwrap_transaction()
  end

  def run(_context, _fun), do: {:error, :missing_ownership_scope}

  def current_setting(name) when name in ["app.organization_id", "app.user_id"] do
    case Ecto.Adapters.SQL.query(Repo, "SELECT current_setting($1, true)", [name]) do
      {:ok, %{rows: [[value]]}} -> value
      _error -> nil
    end
  end

  defp maybe_set_user(%{user_id: user_id}) when is_binary(user_id),
    do: set_local("app.user_id", user_id)

  defp maybe_set_user(_context), do: :ok

  defp set_local(name, value) do
    Ecto.Adapters.SQL.query!(Repo, "SELECT set_config($1, $2, true)", [name, value])
    :ok
  end

  defp unwrap_transaction({:ok, result}), do: result
  defp unwrap_transaction({:error, reason}), do: {:error, reason}
end
