defmodule MilosTraining.Application.ResolveTenantContext do
  alias MilosTraining.Organizations

  def call(account, slug, request_metadata),
    do: Organizations.resolve_tenant_context(account, slug, request_metadata)
end
