defmodule Palee.Application.Fiscal.PaymentDocumentsTest do
  @moduledoc """
  ADR-262: money recorded at the desk or online issues its fiscal document
  once the business's fiscal identity is complete, once per payment.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Fiscal, Organizations}
  alias Palee.Application.Fiscal.PaymentDocuments

  @identity %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    street: "Ερμού",
    postal_code: "10563",
    city: "Αθήνα"
  }

  setup %{conn: conn} do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})
    {organization, context} = tenant_fixture(admin, "Fiscal Payments")
    add_tenant_member(organization, member, :member)

    {:ok, package} =
      Finance.create_package(context, %{
        name: "Unlimited",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6_200
      })

    {:ok, membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    {:ok, subscription} = Finance.assign_package(context, membership.id, package.id, %{})

    %{
      admin: admin,
      context: context,
      conn: put_bearer_token(conn, admin),
      path: "/api/org/#{organization.slug}/admin/finance/members/#{member.id}/receipts",
      subscription: subscription
    }
  end

  defp receipt(ctx, key) do
    ctx.conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> post(
      ctx.path,
      Jason.encode!(%{
        amount_cents: 6_200,
        payment_method: "card_manual",
        paid_on: Date.to_iso8601(Date.utc_today()),
        description: "Monthly membership",
        membership_package_subscription_id: ctx.subscription.id,
        idempotency_key: key
      })
    )
    |> json_response(201)
    |> Map.fetch!("receipt")
  end

  test "without a fiscal identity the payment keeps Finance's document only", ctx do
    assert %{"fiscal_document" => nil, "payment" => %{"amount_cents" => 6_200}} =
             receipt(ctx, Ecto.UUID.generate())

    assert Fiscal.list_documents(ctx.context) |> documents() == []
  end

  test "with a complete identity the desk payment issues its receipt once", ctx do
    {:ok, _identity} =
      Fiscal.save_identity(ctx.context, @identity, ctx.admin.id, DateTime.utc_now())

    received = receipt(ctx, Ecto.UUID.generate())

    assert %{"kind" => "receipt", "gross_cents" => 6_200, "currency" => "EUR"} =
             received["fiscal_document"]

    [document] = Fiscal.list_documents(ctx.context) |> documents()
    assert document.source_type == "finance_payment"
    assert document.source_id == received["payment"]["id"]
    assert document.payment_method == "card"

    # The same payment never issues a second document.
    assert {:ok, %{id: id}} =
             PaymentDocuments.issue(
               ctx.context,
               %{payment: %{id: received["payment"]["id"]}, invoice: nil},
               ctx.admin.id,
               DateTime.utc_now()
             )

    assert id == document.id
  end

  test "a part refund at the desk credits the receipt by the amount given back", ctx do
    {:ok, _identity} =
      Fiscal.save_identity(ctx.context, @identity, ctx.admin.id, DateTime.utc_now())

    received = receipt(ctx, Ecto.UUID.generate())

    reversals =
      String.replace(ctx.path, "/receipts", "/payments/#{received["payment"]["id"]}/reversals")

    request_id = Ecto.UUID.generate()

    refund = fn ->
      ctx.conn
      |> recycle()
      |> put_req_header("content-type", "application/json")
      |> post(
        reversals,
        Jason.encode!(%{amount_cents: 2_000, reason: "Injury", request_id: request_id})
      )
      |> json_response(201)
      |> Map.fetch!("payment_reversal")
    end

    first = refund.()

    assert %{"kind" => "credit_note", "gross_cents" => 2_000} = first["fiscal_credit_note"]

    # Replaying the same refund returns the same credit note.
    assert refund.()["fiscal_credit_note"]["id"] == first["fiscal_credit_note"]["id"]

    [_note] =
      ctx.context
      |> Fiscal.list_documents(%{kind: "credit_note"})
      |> documents()
  end

  defp tenant_fixture(user, name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    add_tenant_member(organization, user, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    {organization, context}
  end

  defp add_tenant_member(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp documents(%{documents: documents}), do: documents
  defp documents(documents) when is_list(documents), do: documents
end
