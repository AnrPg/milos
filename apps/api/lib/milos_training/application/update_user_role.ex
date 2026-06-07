defmodule MilosTraining.Application.UpdateUserRole do
  alias MilosTraining.Identity

  def call(user_id, params) when is_map(params) do
    role = Map.get(params, "role") || Map.get(params, :role)

    with {:ok, updated_user} <- Identity.update_role(user_id, role) do
      {:ok, updated_user}
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
