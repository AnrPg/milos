defmodule Palee.Organizations.Commands.RedeemInvitation do
  alias Palee.Identity
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{GoLivePolicy, InvitationEmail, InvitationToken}
  alias Palee.Organizations.OrganizationStore

  def call(token, user_id, redeemed_at) do
    with {:ok, digest} <- InvitationToken.decode(token),
         {:ok, proof} <- authorize_intended_email(digest, user_id),
         :ok <- authorize_live_organization(digest) do
      # The redeemer is not yet a member of the organization they are joining,
      # so this runs under the invitation carve-out (F-16).
      RepoContext.run(%{invitation_redemption: true, user_id: user_id}, fn ->
        OrganizationStore.redeem_invitation(digest, user_id, redeemed_at)
      end)
      |> hide_invitation_state()
      |> mark_inbox_proven(proof, redeemed_at)
    end
  end

  # F-10: an invitation issued to a specific address may only be redeemed by
  # an account holding that address. Invitations issued without one carry a
  # nil digest and stay open to whoever holds the token.
  #
  # ADR-209: a bound invitation a business issued
  # (`email_verification_required`) also needs the login to have proved it
  # reads that address: either its email is verified, or the token went only
  # into an email (`emailed_at`), so opening it proves the inbox and the
  # redemption marks the address verified. Answers `{:ok, account}` when the
  # redemption proves the inbox, `{:ok, nil}` otherwise.
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
        {:ok, nil}

      %{intended_email_digest: nil} ->
        {:ok, nil}

      %{intended_email_digest: intended} = invitation ->
        account = Identity.find_by_id(user_id)

        if InvitationEmail.matches?(intended, account_email(account)) do
          InvitationEmail.redemption_proof(invitation, Identity.email_verified?(account), account)
        else
          {:error, :invitation_email_mismatch}
        end
    end
  end

  defp mark_inbox_proven({:ok, _redemption} = result, %{login_id: login_id, email: email}, now)
       when is_binary(login_id) do
    # The address matched a moment ago; a mismatch here only means the
    # login's email changed in between, and then nothing is marked.
    _marked = Identity.mark_email_verified(login_id, email, now)
    result
  end

  defp mark_inbox_proven(result, _proof, _now), do: result

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

  defp account_email(%{email: email}), do: email
  defp account_email(_missing), do: nil

  defp hide_invitation_state({:error, reason})
       when reason in [:invalid_invitation, :not_found],
       do: {:error, :invalid_invitation}

  defp hide_invitation_state(result), do: result
end
