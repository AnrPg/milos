defmodule PaleeWeb.AdminFiscalReportingControllerTest do
  @moduledoc """
  ADR-243 over HTTP: owners connect myDATA (the key is never returned),
  staff with finance reports see each document's report, owners retry a
  refused one; front desk (by default) and coaches cannot.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Fiscal, Organizations, Repo}

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    staff = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = staff.(:owner)
    {_accountant_user, accountant} = staff.(:accountant)
    {_desk_user, desk} = staff.(:front_desk)
    {_coach_user, coach} = staff.(:coach)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    %{
      context: context,
      owner_user: owner_user,
      owner: owner,
      accountant: accountant,
      desk: desk,
      coach: coach,
      admin: "/api/org/#{Organizations.legacy_organization_slug()}/admin"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  @identity %{
    "legal_name" => "CrossFit Αθήνα ΙΚΕ",
    "country_code" => "GR",
    "tax_id" => "090000045",
    "tax_office" => "Α' Αθηνών",
    "street" => "Ερμού",
    "postal_code" => "10563",
    "city" => "Αθήνα"
  }

  test "the connection is saved per environment and never shows the key", ctx do
    path = "#{ctx.admin}/fiscal/authority-connection"

    assert %{"connection" => nil, "environments" => ["sandbox", "test", "production"]} =
             ctx.owner |> get_json(path) |> json_response(200)

    assert %{"code" => "validation_failed", "errors" => %{"user_id" => ["required"]}} =
             ctx.owner
             |> send_json(:put, path, %{"environment" => "production"})
             |> json_response(422)

    assert %{"connection" => connection} =
             ctx.owner
             |> send_json(:put, path, %{
               "environment" => "test",
               "user_id" => "boxuser",
               "subscription_key" => "secret-key"
             })
             |> json_response(200)

    assert connection["has_subscription_key"]
    refute Map.has_key?(connection, "subscription_key")

    body = ctx.accountant |> get_json(path) |> json_response(200)
    refute inspect(body) =~ "secret-key"

    assert ctx.desk |> send_json(:put, path, %{"environment" => "sandbox"}) |> json_response(403)
    assert ctx.coach |> get_json(path) |> json_response(403)
  end

  test "documents show their report; transmissions list and retry", ctx do
    ctx.owner |> send_json(:put, "#{ctx.admin}/fiscal/identity", @identity) |> json_response(200)

    ctx.owner
    |> send_json(:put, "#{ctx.admin}/fiscal/authority-connection", %{"environment" => "sandbox"})
    |> json_response(200)

    now = DateTime.utc_now()

    {:ok, document, :issued} =
      Fiscal.issue(
        ctx.context,
        %{
          kind: "receipt",
          issue_date: Organizations.local_date(ctx.context, now),
          idempotency_key: "sale-1",
          lines: [%{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: 6000}]
        },
        ctx.owner_user.id,
        now
      )

    assert %{"documents" => [%{"transmission" => %{"status" => "pending"}}]} =
             ctx.accountant |> get_json("#{ctx.admin}/fiscal/documents") |> json_response(200)

    Palee.Application.Fiscal.FiscalReporting.transmit(ctx.context)

    assert %{"document" => %{"transmission" => %{"status" => "accepted", "mark" => "9000" <> _}}} =
             ctx.owner
             |> get_json("#{ctx.admin}/fiscal/documents/#{document.id}")
             |> json_response(200)

    assert %{"total" => 1, "counts" => %{"accepted" => 1}, "transmissions" => [row]} =
             ctx.accountant
             |> get_json("#{ctx.admin}/fiscal/transmissions?status=accepted")
             |> json_response(200)

    refute Map.has_key?(row, "organization_id")

    assert %{"code" => "not_retryable"} =
             ctx.owner
             |> send_json(
               :post,
               "#{ctx.admin}/fiscal/documents/#{document.id}/transmission/retry",
               %{}
             )
             |> json_response(409)

    assert ctx.desk
           |> send_json(
             :post,
             "#{ctx.admin}/fiscal/documents/#{document.id}/transmission/retry",
             %{}
           )
           |> json_response(403)
  end
end
