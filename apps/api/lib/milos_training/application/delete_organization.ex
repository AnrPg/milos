defmodule MilosTraining.Application.DeleteOrganization do
  alias MilosTraining.{Identity, Organizations}

  def call(platform_context, organization_id) do
    with {:ok, user_ids} <-
           Organizations.list_deletable_organization_user_ids(platform_context, organization_id),
         :ok <- delete_users(user_ids),
         {:ok, organization} <-
           Organizations.delete_organization(platform_context, organization_id) do
      {:ok, organization}
    end
  end

  defp delete_users(user_ids) do
    Enum.reduce_while(user_ids, :ok, fn user_id, :ok ->
      case Identity.find_by_id(user_id) do
        nil ->
          {:cont, :ok}

        user ->
          case Identity.delete(user) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
      end
    end)
  end
end
