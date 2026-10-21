defmodule Palee.Application.ResolveTenantContext do
  alias Palee.Organizations

  def call(account, slug, request_metadata),
    do: Organizations.resolve_tenant_context(account, slug, request_metadata)
end
