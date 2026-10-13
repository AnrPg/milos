defmodule MilosTraining.Application.ProvisionOrganization do
  @moduledoc """
  Vendor provisioning: the organization, its settings, initial admin
  invitation and audit event (Organizations) and the tenant defaults
  (`TenantDefaults`, e.g. ADR-128 scale levels) commit or roll back together
  (ADR-133). Organizations runs the seed inside its creation transaction, in
  the new tenant's scope.
  """

  alias MilosTraining.Application.TenantDefaults
  alias MilosTraining.Organizations

  def call(platform_context, params),
    do:
      Organizations.provision_organization(platform_context, params,
        seed_defaults: &TenantDefaults.call/1
      )
end
