defmodule MilosTraining.Application.GetAdminUserProfile do
  @moduledoc false

  alias MilosTraining.Application.TenantUserAccess
  alias MilosTraining.Identity.Domain.AdminProfilePolicy

  def call(user_id, tenant_context, organization_slug \\ nil) do
    case TenantUserAccess.fetch_active_user(tenant_context, user_id) do
      {:ok, user} ->
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
             operational_links: AdminProfilePolicy.operational_links(user, organization_slug)
           }
         }}

      error ->
        error
    end
  end

  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(_value), do: nil
end
