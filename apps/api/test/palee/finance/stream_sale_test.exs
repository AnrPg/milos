defmodule Palee.Finance.StreamSaleTest do
  @moduledoc """
  ADR-264: `Finance.record_stream_sale/2` writes a sale paid on the spot
  (invoice, lines and payment) at once, idempotent per the payment's
  source, and money with no membership is allowed for the shop, event and
  other streams only.
  """

  use Palee.DataCase, async: false

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations}
  alias Palee.Payments.Domain.TerminalSale

  setup do
    admin = admin_fixture()

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Stream Sale #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    %{context: context}
  end

  defp intent(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        provider: "viva",
        provider_transaction_id: "tx-" <> Ecto.UUID.generate(),
        purpose_type: "free_sale",
        amount_cents: 1_500,
        currency: "EUR",
        description: "Drop-in",
        metadata: %{"walk_in" => true},
        tip_cents: 0,
        surcharge_cents: 20,
        created_by_id: nil
      },
      attrs
    )
  end

  test "a walk-in's sale is written once, paid, with no membership", %{context: context} do
    intent = intent()
    sale = TerminalSale.walk_in(intent, Date.utc_today(), %{surcharge: "Card surcharge"})

    assert {:ok, first} = Finance.record_stream_sale(context, sale)
    refute first.replayed
    assert first.invoice.status == "paid"
    assert first.invoice.membership_id == nil
    assert first.invoice.total_cents == 1_520
    assert length(first.invoice.lines) == 2
    assert first.payment.amount_cents == 1_520
    assert first.payment.finance_invoice_id == first.invoice.id

    # The same source again: the first sale, nothing new.
    assert {:ok, again} = Finance.record_stream_sale(context, sale)
    assert again.replayed
    assert again.payment.id == first.payment.id
    assert again.invoice.id == first.invoice.id
    assert length(again.invoice.lines) == 2

    assert [_one] = Finance.revenue_lineage(context, "walk_in_sale", intent.id).payments
  end

  test "membership money still needs its membership", %{context: context} do
    sale = TerminalSale.walk_in(intent(), Date.utc_today(), %{surcharge: "Card surcharge"})

    membership_sale =
      sale
      |> put_in(["invoice", "revenue_stream"], "membership")
      |> put_in(["payment", "revenue_stream"], "membership")

    assert {:error, %Ecto.Changeset{} = changeset} =
             Finance.record_stream_sale(context, membership_sale)

    assert {"is invalid", _detail} = changeset.errors[:membership_id]

    assert Finance.revenue_lineage(context, "walk_in_sale", sale["payment"]["source_id"]).payments ==
             []
  end
end
