defmodule Palee.Organizations.Queries.EmailedInvitations do
  @moduledoc """
  ADR-209: reads behind invitations sent by email, in the acting staff
  member's tenant scope: one invitation of the box (for a resend) and how
  many the box and the inviter emailed since a time (the daily caps).
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.TenantAuthorization
  alias Palee.Organizations.OrganizationStore

  def get(context, invitation_id) do
    with :ok <- TenantAuthorization.authorize_capability(context, :invite_clients),
         {:ok, _uuid} <- Ecto.UUID.cast(invitation_id) do
      case RepoContext.run(context, fn ->
             OrganizationStore.get_invitation(context.organization_id, invitation_id)
           end) do
        nil -> {:error, :invalid_invitation}
        invitation -> {:ok, invitation}
      end
    else
      :error -> {:error, :invalid_invitation}
      error -> error
    end
  end

  def count_since(context, since) do
    RepoContext.run(context, fn ->
      OrganizationStore.count_emailed_invitations(context.organization_id, context.user_id, since)
    end)
  end
end
