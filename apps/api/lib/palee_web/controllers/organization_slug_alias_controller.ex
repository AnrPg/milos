defmodule PaleeWeb.OrganizationSlugAliasController do
  @moduledoc """
  ADR-122: unauthenticated retired-slug lookup used by the web proxy to issue
  a 308 from `/org/<old>/...` to `/org/<new>/...`.

  It answers only for retired aliases and reveals nothing beyond the current
  slug; canonical and unknown slugs are an identical 404, so it cannot be used
  to probe whether an organization exists.
  """
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ResolveOrganizationSlugAlias
  alias OpenApiSpex.{Parameter, Schema}

  tags(["Organizations"])

  operation(:show,
    summary: "Resolve a retired organization slug to its current canonical slug",
    parameters: [
      %Parameter{name: :slug, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok:
        {"Canonical slug for a retired alias", "application/json",
         %Schema{
           type: :object,
           properties: %{
             slug: %Schema{type: :string},
             canonical_slug: %Schema{type: :string},
             canonical_path: %Schema{type: :string}
           },
           required: [:slug, :canonical_slug, :canonical_path]
         }},
      not_found:
        {"Not a retired alias", "application/json",
         %Schema{
           type: :object,
           properties: %{code: %Schema{type: :string}, error: %Schema{type: :string}},
           required: [:code]
         }}
    ]
  )

  def show(conn, %{"slug" => slug}) do
    case ResolveOrganizationSlugAlias.call(slug) do
      {:ok, canonical_slug} ->
        conn
        # Short shared cache: renames are rare, and the proxy caches too.
        |> put_resp_header("cache-control", "public, max-age=60")
        |> json(%{
          slug: slug,
          canonical_slug: canonical_slug,
          canonical_path: "/org/#{canonical_slug}"
        })

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          code: "organization_slug_alias_not_found",
          error: "Not a retired organization slug"
        })
    end
  end
end
