defmodule MilosTraining.Application.InspectRegistrationInvitation do
  alias MilosTraining.Organizations

  def call(token), do: Organizations.inspect_invitation(token)
end
