defmodule MilosTraining.Application.IssueRegistrationInvitation do
  alias MilosTraining.Organizations

  def call(context, params), do: Organizations.issue_invitation(context, params)
end
