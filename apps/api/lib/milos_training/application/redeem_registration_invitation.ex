defmodule MilosTraining.Application.RedeemRegistrationInvitation do
  alias MilosTraining.Organizations

  def call(%{id: user_id}, token), do: Organizations.redeem_invitation(token, user_id)
end
