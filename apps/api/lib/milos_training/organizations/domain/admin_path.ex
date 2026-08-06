defmodule MilosTraining.Organizations.Domain.AdminPath do
  @moduledoc """
  Builds organization-scoped admin URLs for links the backend hands to clients
  (push notification deep links, operational links in admin payloads).

  Mirrors `adminHref` in `apps/web/src/lib/organization-slug.ts`: a known slug
  produces `/org/:slug/admin/...`, an unknown one falls back to the bare path
  rather than emitting a broken link. Falling back is safe — the backend
  rejects header-derived tenants unconditionally (F-01), so a bare path costs
  the user a redirect, never a cross-tenant read.
  """

  def admin_url(path, organization_slug)

  def admin_url("/" = path, _organization_slug), do: path

  def admin_url(path, organization_slug)
      when is_binary(path) and is_binary(organization_slug) and organization_slug != "",
      do: "/org/#{organization_slug}#{path}"

  def admin_url(path, _organization_slug) when is_binary(path), do: path
end
