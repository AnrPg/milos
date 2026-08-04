defmodule MilosTraining.Infrastructure.Tenancy.RepoContext do
  alias MilosTraining.Repo

  def run(%{organization_id: organization_id} = context, fun)
      when is_binary(organization_id) and is_function(fun, 0) do
    with_settings([{"app.organization_id", organization_id} | contextual_settings(context)], fun)
  end

  def run(%{user_id: user_id} = context, fun) when is_binary(user_id) and is_function(fun, 0) do
    with_settings(contextual_settings(context), fun)
  end

  def run(_context, _fun), do: {:error, :missing_ownership_scope}

  def current_setting(name)
      when name in [
             "app.organization_id",
             "app.user_id",
             "app.admin_mode",
             "app.execution_authorization_check"
           ] do
    case Ecto.Adapters.SQL.query(Repo, "SELECT current_setting($1, true)", [name]) do
      {:ok, %{rows: [[value]]}} when value in [nil, ""] -> nil
      {:ok, %{rows: [[value]]}} -> value
      _error -> nil
    end
  end

  defp with_settings(settings, fun) do
    Repo.checkout(fn ->
      previous = Map.new(settings, fn {name, _value} -> {name, current_setting(name)} end)

      Enum.each(settings, fn {name, value} -> set_session(name, value) end)

      try do
        fun.()
      after
        Enum.each(previous, fn {name, value} -> set_session(name, value || "") end)
      end
    end)
  end

  defp contextual_settings(context) do
    []
    |> maybe_put_user(context)
    |> maybe_put_admin_mode(context)
    |> maybe_put_execution_authorization_check(context)
  end

  defp maybe_put_user(settings, %{user_id: user_id}) when is_binary(user_id),
    do: [{"app.user_id", user_id} | settings]

  defp maybe_put_user(settings, _context), do: settings

  defp maybe_put_admin_mode(settings, %{account: %{role: role}}) do
    if to_string(role) == "admin" do
      [{"app.admin_mode", "true"} | settings]
    else
      settings
    end
  end

  defp maybe_put_admin_mode(settings, _context), do: settings

  defp maybe_put_execution_authorization_check(settings, %{execution_authorization_check: true}),
    do: [{"app.execution_authorization_check", "true"} | settings]

  defp maybe_put_execution_authorization_check(settings, _context), do: settings

  defp set_session(name, value) do
    Ecto.Adapters.SQL.query!(Repo, "SELECT set_config($1, $2, false)", [name, value])
    :ok
  end
end
