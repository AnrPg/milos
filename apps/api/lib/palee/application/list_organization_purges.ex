defmodule Palee.Application.ListOrganizationPurges do
  @moduledoc "Recent platform purge records (the audit trail that survives purges)."

  alias Palee.Organizations

  def call(platform_context), do: Organizations.list_organization_purges(platform_context)
end
