defmodule MilosTraining.Application.RemoveOrganizationLogo do
  @moduledoc """
  ADR-121: clears an organization's logo (uploaded or legacy external URL),
  records the audit event and deletes the uploaded object, prefix-pinned.
  """

  alias MilosTraining.Application.OrganizationLogo
  alias MilosTraining.Organizations

  def call(context, organization_id \\ nil) do
    with {:ok, organization_id} <-
           OrganizationLogo.resolve_organization(context, organization_id),
         {:ok, result} <- Organizations.remove_organization_logo(context, organization_id) do
      OrganizationLogo.after_change(organization_id, result)
    end
  end
end
