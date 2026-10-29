defmodule Palee.Payments.Domain.WithdrawalTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.Withdrawal

  @now ~U[2027-02-05 10:00:00.000000Z]

  test "applies in the EU, the EEA and the UK, not elsewhere" do
    for country <- ~w(GR CY DE AT FR BE LU NO GB gr), do: assert(Withdrawal.applies?(country))
    for country <- ["CH", "US", "CA", nil], do: refute(Withdrawal.applies?(country))
  end

  test "buying where it applies needs the express request to start now" do
    assert Withdrawal.record(true, %{start_now: false}, @now) ==
             {:error, :start_now_consent_required}

    assert {:ok, record} = Withdrawal.record(true, %{start_now: true, language: "el"}, @now)
    assert record["applies"]
    assert record["deadline"] == DateTime.to_iso8601(DateTime.add(@now, 14 * 86_400, :second))
    assert Withdrawal.record(false, %{}, @now) == {:ok, %{"applies" => false}}
  end

  test "open within 14 days only" do
    {:ok, record} = Withdrawal.record(true, %{start_now: true}, @now)
    assert Withdrawal.open?(record, DateTime.add(@now, 13 * 86_400, :second)) == :ok

    assert Withdrawal.open?(record, DateTime.add(@now, 15 * 86_400, :second)) ==
             {:error, :withdrawal_period_over}

    assert Withdrawal.open?(%{"applies" => false}, @now) == {:error, :withdrawal_not_available}
  end

  test "the refund is the price less the larger of the time or visits used" do
    facts = %{
      starts_on: ~D[2027-02-01],
      ends_on: ~D[2027-03-03],
      visits_used: 0,
      visits_total: nil
    }

    assert Withdrawal.refund_cents(6_000, facts, ~D[2027-02-01]) == 6_000
    assert Withdrawal.refund_cents(6_000, facts, ~D[2027-02-04]) == 5_400

    pack = %{facts | visits_used: 5, visits_total: 10}
    assert Withdrawal.refund_cents(6_000, pack, ~D[2027-02-04]) == 3_000
    assert Withdrawal.refund_cents(6_000, %{pack | visits_used: 12}, ~D[2027-02-04]) == 0
  end
end
