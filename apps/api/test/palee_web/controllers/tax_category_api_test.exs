defmodule PaleeWeb.TaxCategoryApiTest do
  @moduledoc """
  ADR-244 over HTTP: membership packages, shop products and variants carry
  a tax category (and an exemption reason when exempt), checked against
  the business's country; the deprecated variant `tax_class` stays in sync.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)

    %{
      owner: put_bearer_token(conn, owner),
      admin: "/api/org/#{organization.slug}/admin",
      staff: "/api/org/#{organization.slug}/staff/shop"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp greek_identity(ctx) do
    ctx.owner
    |> send_json(:put, "#{ctx.admin}/fiscal/identity", %{
      "legal_name" => "CrossFit Αθήνα ΙΚΕ",
      "country_code" => "GR",
      "tax_id" => "090000045",
      "tax_office" => "Α' Αθηνών",
      "street" => "Ερμού",
      "postal_code" => "10563",
      "city" => "Αθήνα"
    })
    |> json_response(200)
  end

  @package %{
    code: "tax_unlimited",
    name: "Unlimited",
    package_type: "membership",
    billing_period: "monthly",
    base_price_cents: 6_000
  }

  test "packages take a tax category valid in the business's country", ctx do
    greek_identity(ctx)
    path = "#{ctx.admin}/finance/packages"

    assert %{"package" => %{"id" => id, "tax_category" => nil, "exemption_reason" => nil}} =
             ctx.owner |> send_json(:post, path, @package) |> json_response(201)

    assert %{"errors" => %{"tax_category" => ["not_available_in_country"]}} =
             ctx.owner
             |> send_json(:patch, "#{path}/#{id}", %{tax_category: "sales_tax"})
             |> json_response(422)

    assert %{"errors" => %{"exemption_reason" => _required}} =
             ctx.owner
             |> send_json(:patch, "#{path}/#{id}", %{tax_category: "exempt"})
             |> json_response(422)

    assert %{"package" => %{"tax_category" => "exempt", "exemption_reason" => "Άρθρο 22 ΚΦΠΑ"}} =
             ctx.owner
             |> send_json(:patch, "#{path}/#{id}", %{
               tax_category: "exempt",
               exemption_reason: "Άρθρο 22 ΚΦΠΑ"
             })
             |> json_response(200)

    assert %{"package" => %{"tax_category" => "reduced", "exemption_reason" => nil}} =
             ctx.owner
             |> send_json(:patch, "#{path}/#{id}", %{tax_category: "reduced"})
             |> json_response(200)

    assert ctx.owner
           |> send_json(:post, path, Map.merge(@package, %{code: "tax_bad", tax_category: "luxury"}))
           |> json_response(422)
  end

  test "products and variants carry categories; tax_class follows tax_category", ctx do
    greek_identity(ctx)

    assert %{"product" => %{"id" => id, "tax_category" => "reduced", "variants" => [variant]}} =
             ctx.owner
             |> send_json(:post, "#{ctx.staff}/products", %{
               title: "Protein bar",
               category: "nutrition",
               tax_category: "reduced",
               variants: [%{sku: "BAR-1", price_cents: 300, tax_category: "super_reduced"}]
             })
             |> json_response(201)

    assert variant["tax_category"] == "super_reduced"
    assert variant["tax_class"] == "super_reduced"

    variant_path = "#{ctx.staff}/products/#{id}/variants/#{variant["id"]}"

    assert %{"variant" => %{"tax_category" => "standard", "tax_class" => "standard"}} =
             ctx.owner |> send_json(:patch, variant_path, %{tax_class: "standard"}) |> json_response(200)

    assert %{"variant" => %{"tax_category" => "zero", "tax_class" => nil}} =
             ctx.owner |> send_json(:patch, variant_path, %{tax_category: "zero"}) |> json_response(200)

    assert %{"errors" => %{"tax_category" => ["not_available_in_country"]}} =
             ctx.owner
             |> send_json(:patch, "#{ctx.staff}/products/#{id}", %{tax_category: "sales_tax"})
             |> json_response(422)
  end
end
