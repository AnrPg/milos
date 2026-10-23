defmodule Palee.Organizations.Commands.RedeemInvitation do
  alias Palee.Identity
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, InvitationEmail, InvitationToken}
  alias Palee.Organizations.OrganizationStore

  def call(token, user_id, redeemed_at) do
    with {:ok, digest} <- InvitationToken.decode(token),
         :ok <- authorize_intended_email(digest, user_id),
         :ok <- authorize_live_organization(digest) do
      # The redeemer is not yet a member of the organization they are joining,
      # so this runs under the invitation carve-out (F-16).
      RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
        OrganizationStore.redeem_invitation(digest, user_id, redeemed_at)
      end)
      |> hide_invitation_state()
    end
  end

  # F-10: an invitation issued to a specific address may only be redeemed by
  # an account holding that address. Invitations issued without one carry a
  # nil digest and stay open to whoever holds the token.
  #
  # Checked here rather than inside the store transaction so a mismatch cannot
  # consume the invitation: a wrong account must leave it redeemable by the
  # right one.
  defp authorize_intended_email(digest, user_id) do
    case RepoContext.run(%{invitation_redemption: true}, fn ->
           OrganizationStore.get_invitation_by_digest(digest)
         end) do
      # Let the store's own transaction produce the not-found error, so this
      # check never becomes an oracle for which tokens exist.
      nil ->
        :ok

      %{intended_email_digest: nil} ->
        :ok

      %{intended_email_digest: intended} ->
        if InvitationEmail.matches?(intended, account_email(user_id)) do
          :ok
        else
          {:error, :invitation_email_mismatch}
        end
    end
  end

  # ADR-184: an invitation of a business still in demo mode cannot be
  # redeemed; it answers like any invalid invitation, so the business stays
  # invisible to outsiders.
  defp authorize_live_organization(digest) do
    case RepoContext.run(%{invitation_redemption: true}, fn ->
           OrganizationStore.get_invitation_with_organization(digest)
         end) do
      %{organization: organization} ->
        case GoLivePolicy.check(organization, :join) do
          :ok -> :ok
          {:error, :business_not_activated} -> {:error, :invalid_invitation}
        end

      _none ->
        :ok
    end
  end

  defp account_email(user_id) do
    case Identity.find_by_id(user_id) do
      %{email: email} -> email
      _missing -> nil
    end
  end

  defp hide_invitation_state({:error, reason})
       when reason in [:invalid_invitation, :not_found],
       do: {:error, :invalid_invitation}

  defp hide_invitation_state(result), do: result
end
