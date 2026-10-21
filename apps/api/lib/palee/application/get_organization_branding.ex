defmodule Palee.Application.GetOrganizationBranding do
  @moduledoc "ADR-121: branding settings for the tenant admin settings screen."

  alias Palee.Organizations

  def call(context, organization_id \\ nil),
    do: Organizations.get_organization_branding(context, organization_id)
end
