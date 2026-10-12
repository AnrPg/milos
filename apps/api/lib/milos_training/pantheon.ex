defmodule MilosTraining.Pantheon do
  alias MilosTraining.Application.{
    CreatePR,
    DeletePR,
    EditPR,
    GetPRHistory,
    ListUserPRs,
    SharePR,
    UpdatePR
  }

  defdelegate list_user_prs(user_id, opts \\ []), to: ListUserPRs, as: :call
  defdelegate create_pr(user_id, params), to: CreatePR, as: :call
  defdelegate update_pr(id, user_id, params), to: UpdatePR, as: :call
  defdelegate edit_pr(id, user_id, params), to: EditPR, as: :call
  defdelegate delete_pr(id, user_id), to: DeletePR, as: :call
  defdelegate get_pr_history(id, user_id), to: GetPRHistory, as: :call
  defdelegate share_pr(id, user_id), to: SharePR, as: :call

  # Bounded-context API used by cross-context application orchestration. These
  # operations expose Pantheon capabilities without leaking its store port.
  defdelegate list_records(user_id), to: MilosTraining.Pantheon.PRStore, as: :list_user_prs

  defdelegate search_records(user_id, query),
    to: MilosTraining.Pantheon.PRStore,
    as: :search_user_prs

  defdelegate get_record_for_user(id, user_id),
    to: MilosTraining.Pantheon.PRStore,
    as: :get_pr_for_user

  defdelegate list_organization_records(user_id, organization_id),
    to: MilosTraining.Pantheon.PRStore,
    as: :list_organization_prs

  defdelegate list_record_history(pr_record_id),
    to: MilosTraining.Pantheon.PRStore,
    as: :list_pr_history

  # Every Pantheon read/write is RLS-protected (ADR-111): personal operations
  # run in the acting user's scope, coach reads in the coach's tenant scope.
  def with_user_context(context, fun) when is_function(fun, 0),
    do: MilosTraining.Pantheon.PRStore.with_scope(context, fun)

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: MilosTraining.Pantheon.PRStore.with_scope(context, fun)

  # ADR-111 sharing: coach-visibility opt-out and explicit grants.
  defdelegate get_sharing_preference(user_id),
    to: MilosTraining.Pantheon.PRStore

  defdelegate set_coach_visibility(user_id, enabled?),
    to: MilosTraining.Pantheon.Commands.SetCoachVisibility,
    as: :call

  defdelegate grant_pr_access(user_id, grantee_user_id),
    to: MilosTraining.Pantheon.Commands.GrantPRAccess,
    as: :call

  defdelegate revoke_pr_access(user_id, grant_id),
    to: MilosTraining.Pantheon.Commands.RevokePRAccess,
    as: :call

  defdelegate list_owned_grants(user_id),
    to: MilosTraining.Pantheon.Queries.ListPRAccessGrants,
    as: :owned

  defdelegate list_received_grants(grantee_user_id),
    to: MilosTraining.Pantheon.Queries.ListPRAccessGrants,
    as: :received

  defdelegate read_only_view(pr, history),
    to: MilosTraining.Pantheon.Domain.PRView,
    as: :with_history

  defdelegate create_record(params), to: MilosTraining.Pantheon.PRStore, as: :create_pr
  defdelegate update_record(id, params), to: MilosTraining.Pantheon.PRStore, as: :update_pr
  defdelegate edit_record(id, params), to: MilosTraining.Pantheon.PRStore, as: :edit_pr
  defdelegate delete_record(id, user_id), to: MilosTraining.Pantheon.PRStore, as: :delete_pr

  # ADR-107 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Pantheon.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
