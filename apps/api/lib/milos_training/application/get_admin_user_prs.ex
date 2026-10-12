defmodule MilosTraining.Application.GetAdminUserPRs do
  @moduledoc """
  Staff dossier PR tab (ADR-111).

  Only coaches of the tenant may read members' PRs, and only PRs recorded in
  this tenant, of members with an active membership here who have not opted
  out. The database enforces all of it (`user_pr_records_coach_read_policy`);
  this service adds the role-safe response for staff who are not coaches:
  owners and admins get `visibility: "coach_role_required"` and no records,
  without touching PR data at all.
  """

  alias MilosTraining.{Identity, Organizations, Pantheon}

  def call(context, user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found} do
      if Organizations.acting_user_coaches?(context) do
        prs = Pantheon.with_tenant_context(context, fn -> read(context, user_id) end)
        {:ok, %{user_id: user_id, visibility: "coach", prs: prs}}
      else
        {:ok, %{user_id: user_id, visibility: "coach_role_required", prs: []}}
      end
    end
  end

  defp read(context, user_id) do
    user_id
    |> Pantheon.list_organization_records(context.organization_id)
    |> Enum.map(&Pantheon.read_only_view(&1, Pantheon.list_record_history(&1.id)))
  end
end
