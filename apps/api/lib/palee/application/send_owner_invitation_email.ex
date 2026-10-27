defmodule Palee.Application.SendOwnerInvitationEmail do
  @moduledoc "ADR-210: the vendor console emails an owner invitation and reads its delivery status."

  alias Palee.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.send_owner_invitation_email(platform_context, organization_id, params)

  def deliveries(platform_context, invitation_id),
    do: Organizations.owner_invitation_deliveries(platform_context, invitation_id)
end
