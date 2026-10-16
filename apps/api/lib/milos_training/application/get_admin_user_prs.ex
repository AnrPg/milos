defmodule MilosTraining.Application.GetAdminUserPRs do
  @moduledoc """
  Staff dossier PR tab (ADR-129).

  Only coaches of the tenant may read members' PRs, and only PRs recorded in
  this tenant, of members with an active membership here who have not opted
  out. The database enforces all of it (`user_pr_records_coach_read_policy`);
  this service adds the role-safe response for staff who are not coaches:
  owners and admins get `visibility: "coach_role_required"` and no records,
  without touching PR data at all.

  `member` is the PR owner's public identity when they are an active member of
  this gym (else `nil`), so a coach whose client scope (ADR-100) does not
  reach the full profile can still title the PR dossier (ADR-132).
  """

  alias MilosTraining.Application.{JournalComments, TenantUserAccess}
  alias MilosTraining.{Identity, Organizations, Pantheon}

  def call(context, user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found} do
      member = member(context, user_id)

      if Organizations.acting_user_coaches?(context) do
        prs = Pantheon.with_tenant_context(context, fn -> read(context, user_id) end)
        {:ok, %{user_id: user_id, visibility: "coach", member: member, prs: prs}}
      else
        {:ok, %{user_id: user_id, visibility: "coach_role_required", member: member, prs: []}}
      end
    end
  end

  defp member(context, user_id) do
    case TenantUserAccess.fetch_active_user(context, user_id) do
      {:ok, user} -> %{id: user.id, nickname: user.nickname, avatar_url: user.avatar_url}
      _not_active_here -> nil
    end
  end

  defp read(context, user_id) do
    user_id
    |> Pantheon.list_organization_records(context.organization_id)
    |> JournalComments.attach("pr")
    |> Enum.map(fn pr ->
      pr
      |> Pantheon.read_only_view(Pantheon.list_record_history(pr.id))
      |> Map.put(:comments, pr.comments)
    end)
  end
end
