defmodule Palee.Finance.Domain.TransactionFeedTest do
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.TransactionFeed

  @box "11111111-1111-1111-1111-111111111111"
  @other "22222222-2222-2222-2222-222222222222"

  defp party(id), do: %{organization_id: id, name: nil, kind: "gym", slug: nil}

  defp entries do
    [
      TransactionFeed.entry(
        "invoice",
        "i1",
        party(@box),
        "INV-1",
        5000,
        nil,
        :issued,
        ~D[2026-10-01],
        %{}
      ),
      TransactionFeed.entry(
        "payment",
        "p1",
        party(@box),
        nil,
        5000,
        "EUR",
        "paid",
        ~D[2026-10-02],
        %{}
      ),
      TransactionFeed.entry(
        "payment",
        "p0",
        party(@other),
        nil,
        900,
        "EUR",
        "paid",
        ~D[2026-10-02],
        %{}
      ),
      TransactionFeed.entry(
        "event_payment",
        "a1",
        party(@other),
        "Open",
        1500,
        "EUR",
        "paid",
        ~U[2026-10-03 09:00:00Z],
        %{}
      ),
      TransactionFeed.entry("refund", "r1", party(@box), nil, -1000, "EUR", "refund", nil, %{})
    ]
  end

  defp page(opts) do
    TransactionFeed.page(
      entries(),
      Map.merge(
        %{scope: nil, provider_ids: MapSet.new([@box]), kind: nil, cursor: nil, limit: 30},
        opts
      )
    )
  end

  test "entries are newest first, ties broken by id, undated last" do
    assert %{transactions: rows, total: 5, next_cursor: nil} = page(%{})

    assert Enum.map(rows, & &1.id) ==
             ~w(event_payment:a1 payment:p1 payment:p0 invoice:i1 refund:r1)

    assert hd(rows).currency == "EUR" and Enum.at(rows, 3).status == "issued"
    refute Map.has_key?(hd(rows), :sort)
    assert hd(rows).source_url == nil
  end

  test "pages follow the cursor without repeats" do
    first = page(%{limit: 2})
    assert Enum.map(first.transactions, & &1.source_id) == ~w(a1 p1)
    {:ok, cursor} = TransactionFeed.decode_cursor(first.next_cursor)
    second = page(%{limit: 2, cursor: cursor})
    assert Enum.map(second.transactions, & &1.source_id) == ~w(p0 i1)
  end

  test "a provider scope keeps events at hosts that are not providers" do
    # @other is not a provider: its event ticket stays, its plain payment goes.
    assert %{transactions: rows, total: 4} = page(%{scope: @box})
    assert Enum.map(rows, & &1.source_id) == ~w(a1 p1 i1 r1)
  end

  test "the kind filter narrows after total and kinds are counted" do
    assert %{transactions: [%{id: "refund:r1"}], total: 5, kinds: kinds} = page(%{kind: "refund"})
    assert kinds == ~w(invoice payment refund event_payment)
  end

  test "request params" do
    assert TransactionFeed.decode_cursor("not base64!") == {:error, :invalid_cursor}

    assert TransactionFeed.decode_cursor(Base.url_encode64("nobar", padding: false)) ==
             {:error, :invalid_cursor}

    assert TransactionFeed.decode_cursor("") == {:ok, nil}
    assert TransactionFeed.kind_filter("shop_order") == {:ok, "shop_order"}
    assert TransactionFeed.kind_filter("gift") == {:error, :invalid_kind}
    assert TransactionFeed.limit("500") == 100
    assert TransactionFeed.limit("0") == 1
    assert TransactionFeed.limit("x") == 30
  end

  test "a source link is carried when given" do
    entry =
      TransactionFeed.entry(
        "shop_order",
        "o1",
        party(@box),
        "Order",
        2000,
        "EUR",
        "paid",
        ~D[2026-10-05],
        %{},
        source_url: "/b/box/orders/o1"
      )

    assert entry.id == "shop_order:o1" and entry.source_url == "/b/box/orders/o1"
  end
end
