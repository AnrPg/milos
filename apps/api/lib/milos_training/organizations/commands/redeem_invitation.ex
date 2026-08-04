defmodule MilosTraining.Organizations.Commands.RedeemInvitation do
  alias MilosTraining.Organizations.Domain.InvitationToken
  alias MilosTraining.Organizations.OrganizationStore

  def call(token, user_id, redeemed_at) do
    with {:ok, digest} <- InvitationToken.decode(token) do
      OrganizationStore.redeem_invitation(digest, user_id, redeemed_at)
      |> hide_invitation_state()
    end
  end

  defp hide_invitation_state({:error, reason})
       when reason in [:invalid_invitation, :not_found],
       do: {:error, :invalid_invitation}

  defp hide_invitation_state(result), do: result
end
