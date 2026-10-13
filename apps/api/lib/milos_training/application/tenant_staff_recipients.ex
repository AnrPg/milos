defmodule MilosTraining.Application.TenantStaffRecipients do
  @moduledoc """
  Resolves the staff (owner/admin/coach memberships) of the organization that
  owns an operation, for admin realtime and notification fanout.

  Sources are checked in order — typically the caller's tenant context first,
  then the entity the operation produced — and the first one carrying an
  `organization_id` wins. Without ownership the fanout fails closed to no
  recipients; it never falls back to the global `users.role` admins (ADR-091).
  Personal, user-owned records (ADR-055: self-authored wellbeing facts,
  executions without organization provenance) therefore reach no tenant staff.
  """

  require Logger

  alias MilosTraining.Organizations

  @spec user_ids(term()) :: [Ecto.UUID.t()]
  def user_ids(sources) when is_list(sources) do
    case Enum.find_value(sources, &organization_id/1) do
      nil ->
        Logger.debug("tenant staff fanout skipped: no organization ownership in sources")
        []

      organization_id ->
        Organizations.list_staff_user_ids(organization_id)
    end
  end

  def user_ids(source), do: user_ids([source])

  defp organization_id(organization_id) when is_binary(organization_id), do: organization_id

  defp organization_id(%{organization_id: organization_id}) when is_binary(organization_id),
    do: organization_id

  defp organization_id(%{"organization_id" => organization_id}) when is_binary(organization_id),
    do: organization_id

  defp organization_id(_source), do: nil
end
