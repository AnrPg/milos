defmodule MilosTraining.Application.RedeemRegistrationInvitation do
  alias MilosTraining.Application.ManageCoachingRelationships
  alias MilosTraining.Organizations

  def call(%{id: user_id}, token) do
    with {:ok, redemption} <- Organizations.redeem_invitation(token, user_id) do
      ManageCoachingRelationships.start_invited(
        redemption.organization.id,
        redemption.invitation,
        user_id
      )

      {:ok, redemption}
    end
  end
end
