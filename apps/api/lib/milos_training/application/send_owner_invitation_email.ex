defmodule MilosTraining.Application.SendOwnerInvitationEmail do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.send_owner_invitation_email(platform_context, organization_id, params)
end
