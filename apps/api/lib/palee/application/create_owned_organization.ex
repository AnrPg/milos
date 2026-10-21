defmodule Palee.Application.CreateOwnedOrganization do
  @moduledoc """
  An account that owns a gym creates another one (ADR-099). The gym, its
  settings, the owner membership and the tenant defaults (`TenantDefaults`,
  e.g. ADR-128 scale levels) commit or roll back together (ADR-133).
  """

  alias Palee.Application.TenantDefaults
  alias Palee.Organizations

  def call(account, params),
    do:
      Organizations.create_owned_organization(account, params,
        seed_defaults: &TenantDefaults.call/1
      )
end
