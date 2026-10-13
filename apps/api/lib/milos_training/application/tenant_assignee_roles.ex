defmodule MilosTraining.Application.TenantAssigneeRoles do
  @moduledoc """
  ADR-125: resolves each candidate assignee's **active membership role in the
  acting organization** (user id => role, or nil when the user has no active
  membership there). The global account role is never consulted (F-29).
  """

  alias MilosTraining.Organizations

  def call(%{organization_id: organization_id}, user_ids)
      when is_binary(organization_id) and is_list(user_ids) do
    roles =
      user_ids
      |> Enum.uniq()
      |> Map.new(fn user_id -> {user_id, active_role(user_id, organization_id)} end)

    {:ok, roles}
  end

  def call(_context, _user_ids), do: {:error, :organization_context_required}

  defp active_role(user_id, organization_id) when is_binary(user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.find_value(fn %{membership: membership, organization: organization} ->
      if organization.id == organization_id and membership.status == :active,
        do: membership.role
    end)
  end

  defp active_role(_user_id, _organization_id), do: nil
end
