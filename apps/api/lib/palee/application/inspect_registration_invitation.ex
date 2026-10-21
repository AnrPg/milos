defmodule Palee.Application.InspectRegistrationInvitation do
  alias Palee.Organizations

  def call(token), do: Organizations.inspect_invitation(token)
end
