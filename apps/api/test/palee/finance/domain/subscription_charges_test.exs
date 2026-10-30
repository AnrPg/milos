defmodule Palee.Finance.Domain.SubscriptionChargesTest do
  # ADR-274: what a subscription owes, period by period.
  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{PackageContract, SubscriptionCharges}

  defp params(fields \\ %{"terms.auto_renew" => true}) do
    {:ok, contract} =
      PackageContract.normalize(%{"package_type" => "membership", "fields" => fields})

    PackageContract.to_params(contract)
  end

  defp monthly(overrides \\ %{}) do
    Map.merge(
      %{
        status: "active",
        starts_on: ~D[2026-01-31],
        ends_on: nil,
        billing_period_snapshot: "monthly",
        price_cents_snapshot: 5000,
        corporate_client_id: nil,
        charges_from: ~D[2026-01-31],
        auto_renew: true,
        params_snapshot: params()
      },
      overrides
    )
  end

  test "a priced subscription is billed from its start; a free one or a corporate seat never" do
    assert SubscriptionCharges.charges_from(monthly()) == ~D[2026-01-31]
    assert SubscriptionCharges.charges_from(monthly(%{price_cents_snapshot: 0})) == nil

    assert SubscriptionCharges.charges_from(monthly(%{corporate_client_id: Ecto.UUID.generate()})) ==
             nil
  end

  test "recurring periods count whole months from the start, so the 31st stays the anchor" do
    assert SubscriptionCharges.period_at(monthly(), ~D[2026-01-30]) == nil

    assert SubscriptionCharges.period_at(monthly(), ~D[2026-02-15]) ==
             {~D[2026-01-31], ~D[2026-02-28]}

    assert SubscriptionCharges.period_at(monthly(), ~D[2026-03-30]) ==
             {~D[2026-02-28], ~D[2026-03-31]}

    assert {~D[2026-03-31], ~D[2026-04-30]} =
             SubscriptionCharges.period_at(monthly(), ~D[2026-04-01])

    assert SubscriptionCharges.last_day({~D[2026-03-31], ~D[2026-04-30]}) == ~D[2026-04-29]
  end

  test "due periods: every begun period since charges_from that has no charge, oldest first" do
    renews = fn _start -> true end

    assert [{~D[2026-01-31], ~D[2026-02-28]}, {~D[2026-02-28], ~D[2026-03-31]}] =
             SubscriptionCharges.due_periods(monthly(), [], ~D[2026-03-01], renews)

    assert [{~D[2026-02-28], ~D[2026-03-31]}] =
             SubscriptionCharges.due_periods(monthly(), [~D[2026-01-31]], ~D[2026-03-01], renews)

    # The first period is always owed; later ones only while renewal is open.
    assert [{~D[2026-01-31], _}] =
             SubscriptionCharges.due_periods(monthly(), [], ~D[2026-03-01], fn _ -> false end)

    assert [] =
             SubscriptionCharges.due_periods(
               monthly(%{charges_from: nil}),
               [],
               ~D[2026-03-01],
               renews
             )

    assert [] =
             SubscriptionCharges.due_periods(
               monthly(%{status: "paused"}),
               [],
               ~D[2026-03-01],
               renews
             )
  end

  test "a subscription with an end is not billed for periods after it" do
    subscription = monthly(%{ends_on: ~D[2026-02-10]})

    assert [{~D[2026-01-31], _}] =
             SubscriptionCharges.due_periods(subscription, [], ~D[2026-05-01], fn _ -> true end)
  end

  test "a one-charge package owes once, for its whole length" do
    pack = monthly(%{billing_period_snapshot: "one_off", ends_on: ~D[2026-03-30]})

    assert [{~D[2026-01-31], ~D[2026-03-31]}] =
             SubscriptionCharges.due_periods(pack, [], ~D[2026-02-10], fn _ -> true end)

    assert [] =
             SubscriptionCharges.due_periods(pack, [~D[2026-01-31]], ~D[2026-02-10], fn _ ->
               true
             end)
  end

  test "money recorded without a charge counts against the period it pays for" do
    subscription = monthly()
    receipt = %{service_period_start: nil, issue_date: ~D[2026-01-31], total_cents: 500}

    assert SubscriptionCharges.accounts_for?(subscription, receipt, ~D[2026-01-31])

    refute SubscriptionCharges.accounts_for?(
             subscription,
             %{receipt | issue_date: ~D[2026-02-01]},
             ~D[2026-02-28]
           )

    assert SubscriptionCharges.accounts_for?(
             subscription,
             %{receipt | issue_date: ~D[2026-03-01]},
             ~D[2026-02-28]
           )

    assert SubscriptionCharges.accounts_for?(
             subscription,
             %{service_period_start: ~D[2026-02-28], issue_date: ~D[2026-01-01]},
             ~D[2026-02-28]
           )

    assert SubscriptionCharges.amount_due(subscription, 500) == 4500
    assert SubscriptionCharges.amount_due(subscription, 9000) == 0
  end

  test "the first period's charge is a subscription invoice, later ones renewals" do
    assert SubscriptionCharges.invoice_type(monthly(), ~D[2026-01-31]) == "subscription"
    assert SubscriptionCharges.invoice_type(monthly(), ~D[2026-02-28]) == "renewal"
  end

  test "the current period: its last day, and whether it renews" do
    assert %{starts_on: ~D[2026-02-28], ends_on: ~D[2026-03-30], renews: true} =
             SubscriptionCharges.current_period(monthly(), nil, ~D[2026-03-10])

    assert %{renews: false} =
             SubscriptionCharges.current_period(
               monthly(%{auto_renew: false}),
               nil,
               ~D[2026-03-10]
             )

    assert %{renews: false} =
             SubscriptionCharges.current_period(
               monthly(),
               %{left_at: DateTime.utc_now()},
               ~D[2026-03-10]
             )

    assert %{ends_on: ~D[2026-02-10], renews: false} =
             SubscriptionCharges.current_period(
               monthly(%{ends_on: ~D[2026-02-10]}),
               nil,
               ~D[2026-02-01]
             )

    # Before it starts, the first period.
    assert %{starts_on: ~D[2026-01-31]} =
             SubscriptionCharges.current_period(monthly(), nil, ~D[2026-01-01])
  end
end
