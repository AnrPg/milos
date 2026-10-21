defmodule Palee.Application.ResolveJobTenantContext do
  alias Palee.Organizations

  def call(organization_id, worker) when is_binary(worker) do
    Organizations.resolve_system_tenant_context(organization_id, :oban, %{worker: worker})
  end
end
