defmodule Palee.Payments.Domain.TerminalSaleTest do
  @moduledoc "ADR-264: the Finance rows of a walk-in's sale and a card surcharge."
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.TerminalSale

  @today ~D[2027-02-21]
  @labels %{surcharge: "Επιβάρυνση κάρτας"}

  defp intent(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        provider: "viva",
        provider_transaction_id: "tx-1",
        purpose_type: "free_sale",
        amount_cents: 1_200,
        currency: "EUR",
        description: "Πρωτεΐνη",
        metadata: %{"charge_category" => "product", "walk_in" => true},
        tip_cents: 0,
        surcharge_cents: 0,
        created_by_id: Ecto.UUID.generate()
      },
      attrs
    )
  end

  test "a walk-in's free sale: one memberless line and payment, sourced on the intent" do
    intent = intent()

    %{"invoice" => invoice, "payment" => payment} =
      TerminalSale.walk_in(intent, @today, @labels)

    assert invoice["membership_id"] == nil
    assert invoice["user_id"] == nil
    assert invoice["revenue_stream"] == "other"
    assert invoice["currency"] == "EUR"

    assert [line] = invoice["lines"]
    assert line["source_type"] == "walk_in_sale"
    assert line["source_id"] == intent.id
    assert line["charge_category"] == "product"
    assert line["total_cents"] == 1_200
    assert line["description"] == "Πρωτεΐνη"

    assert payment["source_type"] == "walk_in_sale"
    assert payment["source_id"] == intent.id
    assert payment["membership_id"] == nil
    assert payment["amount_cents"] == 1_200
    assert payment["payment_method"] == "card_terminal"
    assert payment["paid_on"] == @today
    assert payment["params"]["payment_intent_id"] == intent.id
    assert payment["params"]["provider_transaction_id"] == "tx-1"
  end

  test "the surcharge is a second line of the same sale; the tip is not revenue" do
    intent = intent(%{surcharge_cents: 36, tip_cents: 200})

    %{"invoice" => invoice, "payment" => payment} =
      TerminalSale.walk_in(intent, @today, @labels)

    assert [_sale, surcharge] = invoice["lines"]
    assert surcharge["source_type"] == "card_surcharge"
    assert surcharge["description"] == "Επιβάρυνση κάρτας"
    assert surcharge["total_cents"] == 36

    # Base and surcharge; the tip stays on the params only.
    assert payment["amount_cents"] == 1_236
    assert payment["params"]["tip_cents"] == 200
    assert payment["params"]["surcharge_cents"] == 36
  end

  test "an event charge goes to the event stream" do
    intent = intent(%{metadata: %{"charge_category" => "event"}})
    %{"invoice" => invoice, "payment" => payment} = TerminalSale.walk_in(intent, @today, @labels)

    assert invoice["revenue_stream"] == "event"
    assert payment["revenue_stream"] == "event"

    # No category: other.
    %{"payment" => other} = TerminalSale.walk_in(intent(%{metadata: %{}}), @today, @labels)
    assert other["revenue_stream"] == "other"
  end

  test "the surcharge of a member's sale or a shop order is its own sale" do
    member = %{membership_id: Ecto.UUID.generate(), user_id: Ecto.UUID.generate()}
    intent = intent(%{purpose_type: "finance_invoice", surcharge_cents: 90})

    assert TerminalSale.surcharge?(intent)
    refute TerminalSale.surcharge?(intent(%{surcharge_cents: 0}))

    %{"invoice" => invoice, "payment" => payment} =
      TerminalSale.surcharge(intent, member, @today, @labels)

    assert invoice["membership_id"] == member.membership_id
    assert invoice["user_id"] == member.user_id
    assert invoice["revenue_stream"] == "other"
    assert [%{"source_type" => "card_surcharge", "total_cents" => 90}] = invoice["lines"]
    assert payment["amount_cents"] == 90
    assert payment["source_type"] == "card_surcharge"
    assert payment["membership_id"] == member.membership_id

    # A walk-in's shop order: no membership.
    %{"payment" => walk_in} = TerminalSale.surcharge(intent, nil, @today, @labels)
    assert walk_in["membership_id"] == nil
  end
end
