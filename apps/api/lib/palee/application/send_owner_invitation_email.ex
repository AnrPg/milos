defmodule Palee.Application.SendOwnerInvitationEmail do
  alias Palee.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.send_owner_invitation_email(platform_context, organization_id, params)
end
