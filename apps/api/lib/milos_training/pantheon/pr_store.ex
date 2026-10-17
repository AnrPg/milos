defmodule MilosTraining.Pantheon.PRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:milos_training, :pr_store)
  end

  # PRs, history, sharing preferences and grants are RLS-protected: every
  # access runs in an explicit ownership scope - the acting user (personal
  # reads/writes, grantee reads) or the acting coach's tenant (ADR-129).
  def with_scope(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_user_prs(user_id), do: adapter().list_user_prs(user_id)

  @impl true
  def search_user_prs(user_id, query), do: adapter().search_user_prs(user_id, query)

  @impl true
  def get_pr(id), do: adapter().get_pr(id)

  @impl true
  def get_pr_for_user(id, user_id), do: adapter().get_pr_for_user(id, user_id)

  @impl true
  def create_pr(params), do: adapter().create_pr(params)

  @impl true
  def update_pr(id, params), do: adapter().update_pr(id, params)

  @impl true
  def edit_pr(id, params), do: adapter().edit_pr(id, params)

  @impl true
  def delete_pr(id, user_id), do: adapter().delete_pr(id, user_id)

  @impl true
  def list_pr_history(pr_record_id), do: adapter().list_pr_history(pr_record_id)

  @impl true
  def list_user_pr_history(user_id), do: adapter().list_user_pr_history(user_id)

  @impl true
  def count_user_prs(user_id), do: adapter().count_user_prs(user_id)

  @impl true
  def list_organization_prs(user_id, organization_id),
    do: adapter().list_organization_prs(user_id, organization_id)

  @impl true
  def set_record_visibility(id, user_id, rung),
    do: adapter().set_record_visibility(id, user_id, rung)

  @impl true
  def move_records(user_id, from, to), do: adapter().move_records(user_id, from, to)

  @impl true
  def list_record_items(user_id, bound, limit, scope),
    do: adapter().list_record_items(user_id, bound, limit, scope)

  @impl true
  def list_owned_grants(user_id), do: adapter().list_owned_grants(user_id)

  @impl true
  def list_received_grants(grantee_user_id), do: adapter().list_received_grants(grantee_user_id)

  @impl true
  def get_active_grant(user_id, grantee_user_id),
    do: adapter().get_active_grant(user_id, grantee_user_id)

  @impl true
  def create_grant(user_id, grantee_user_id), do: adapter().create_grant(user_id, grantee_user_id)

  @impl true
  def revoke_grant(user_id, grant_id, revoked_at),
    do: adapter().revoke_grant(user_id, grant_id, revoked_at)
end
