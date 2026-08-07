defmodule MilosTraining.Organizations.Commands.RedeemInvitation do
  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.Domain.{InvitationEmail, InvitationToken}
  alias MilosTraining.Organizations.OrganizationStore

  def call(token, user_id, redeemed_at) do
    with {:ok, digest} <- InvitationToken.decode(token),
         :ok <- authorize_intended_email(digest, user_id) do
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
