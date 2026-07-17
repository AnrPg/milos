defmodule MilosTraining.Application.DeleteAdminUser do
  @moduledoc false

  alias MilosTraining.Identity

  def call(user_id, admin_id) do
    with :ok <- prevent_self_delete(user_id, admin_id),
         {:ok, user} <- fetch_user(user_id),
         :ok <- Identity.delete(user) do
      {:ok, %{id: user.id}}
    end
  end

  defp prevent_self_delete(user_id, user_id), do: {:error, :cannot_delete_self}
  defp prevent_self_delete(_user_id, _admin_id), do: :ok

  defp fetch_user(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
