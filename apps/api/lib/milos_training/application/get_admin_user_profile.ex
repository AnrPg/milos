defmodule MilosTraining.Application.GetAdminUserProfile do
  @moduledoc false

  alias MilosTraining.Identity
  alias MilosTraining.Identity.Domain.AdminProfilePolicy

  def call(user_id) do
    case Identity.find_by_id(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        {:ok,
         %{
           user: %{
             identity: %{
               id: user.id,
               nickname: user.nickname,
               role: to_string(user.role),
               avatar_url: user.avatar_url,
               joined_at: timestamp(user.inserted_at)
             },
             account_status: "active",
             available_sections: AdminProfilePolicy.sections(user.role),
             attention: [],
             operational_links: AdminProfilePolicy.operational_links(user)
           }
         }}
    end
  end

  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil
end
