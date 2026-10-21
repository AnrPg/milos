defmodule Palee.Application.RevokeRegistrationInvitation do
  alias Palee.Organizations

  def call(context, invitation_id),
    do: Organizations.revoke_invitation(context, invitation_id)
end
