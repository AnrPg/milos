defmodule MilosTraining.Application.RevokeRegistrationInvitation do
  alias MilosTraining.Organizations

  def call(context, invitation_id),
    do: Organizations.revoke_invitation(context, invitation_id)
end
