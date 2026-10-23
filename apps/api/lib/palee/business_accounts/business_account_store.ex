defmodule Palee.BusinessAccounts.BusinessAccountStore do
  @moduledoc """
  ADR-184: the store facade. Each call opens the session its caller acts in:
  a vendor (`%{user_id: vendor}`), the person themselves (`%{user_id: user}`)
  or the demo business (`%{organization_id, user_id}`).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  def transaction(fun), do: impl().transaction(fun)

  # Activation links: vendors write; the account a link is for reads it.
  def issue_activation_link(%{user_id: _} = scope, attrs, now),
    do: RepoContext.run(scope, fn -> impl().issue_activation_link(attrs, now) end)

  def revoke_activation_link(%{user_id: _} = scope, link_id, now),
    do: RepoContext.run(scope, fn -> impl().revoke_activation_link(link_id, now) end)

  def list_activation_links(%{user_id: _} = scope, organization_ids),
    do: RepoContext.run(scope, fn -> impl().list_activation_links(organization_ids) end)

  def get_activation_link_by_digest(%{user_id: _} = scope, digest),
    do: RepoContext.run(scope, fn -> impl().get_activation_link_by_digest(digest) end)

  def activate_business(%{user_id: _} = scope, digest, now),
    do: RepoContext.run(scope, fn -> impl().activate_business(digest, now) end)

  # Requests: the requester files and reads their own; vendors decide.
  def create_request(%{user_id: _} = scope, attrs),
    do: RepoContext.run(scope, fn -> impl().create_request(attrs) end)

  def get_request(%{user_id: _} = scope, id),
    do: RepoContext.run(scope, fn -> impl().get_request(id) end)

  def list_requests(%{user_id: _} = scope, filters),
    do: RepoContext.run(scope, fn -> impl().list_requests(filters) end)

  def update_request(%{user_id: _} = scope, request, changeset),
    do: RepoContext.run(scope, fn -> impl().update_request(request, changeset) end)

  # Demo records: tenant data of the demo business.
  def track_demo_records(%{organization_id: organization_id} = scope, section, rows),
    do:
      RepoContext.run(scope, fn ->
        impl().track_demo_records(organization_id, section, rows)
      end)

  def list_demo_records(%{organization_id: organization_id} = scope),
    do: RepoContext.run(scope, fn -> impl().list_demo_records(organization_id) end)

  def delete_demo_rows(%{organization_id: organization_id} = scope, records),
    do: RepoContext.run(scope, fn -> impl().delete_demo_rows(organization_id, records) end)

  def clear_demo_records(%{organization_id: organization_id} = scope),
    do: RepoContext.run(scope, fn -> impl().clear_demo_records(organization_id) end)

  def demo_person?(%{organization_id: organization_id} = scope, user_id),
    do: RepoContext.run(scope, fn -> impl().demo_person?(organization_id, user_id) end)

  # A SECURITY DEFINER answer; needs no scope of its own.
  def notification_suppressed?(organization_id, user_id),
    do: impl().notification_suppressed?(organization_id, user_id)

  def deletable_sources, do: impl().deletable_sources()

  defp impl,
    do:
      Application.get_env(
        :palee,
        :business_account_store,
        Palee.Infrastructure.BusinessAccounts.EctoBusinessAccountStore
      )
end
