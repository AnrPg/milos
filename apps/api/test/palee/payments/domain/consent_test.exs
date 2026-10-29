defmodule Palee.Payments.Domain.ConsentTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.Consent

  @now ~U[2027-02-04 10:00:00.000000Z]
  @terms %{
    business: "CrossFit Αθήνα",
    purpose: "τη συνδρομή μου",
    max_amount_cents: 6_500,
    currency: "EUR"
  }

  test "the text names the business, the purpose and the limit" do
    text = Consent.text("el", @terms)
    assert text =~ "«CrossFit Αθήνα»"
    assert text =~ "τη συνδρομή μου"
    assert text =~ "65"
  end

  test "a record keeps the version, the hash of the exact text, when and from where" do
    assert {:ok, record} =
             Consent.record(
               %{accepted: true, language: "el", ip: "203.0.113.9", user_agent: "Safari"},
               @terms,
               @now
             )

    assert record["version"] == Consent.version()
    assert record["text_hash"] == Consent.hash(Consent.text("el", @terms))
    assert record["accepted_at"] == DateTime.to_iso8601(@now)
    assert record["ip"] == "203.0.113.9"
    assert record["max_amount_cents"] == 6_500
    assert record["currency"] == "EUR"
  end

  test "no record without agreement or a limit" do
    assert Consent.record(%{accepted: false}, @terms, @now) == {:error, :consent_required}

    assert Consent.record(%{accepted: true}, %{@terms | max_amount_cents: 0}, @now) ==
             {:error, :invalid_consent_limit}
  end

  test "a saved card is charged only within its consent and before it expires" do
    method = %{
      status: "active",
      currency: "EUR",
      max_amount_cents: 6_500,
      exp_month: 2,
      exp_year: 2027
    }

    today = ~D[2027-02-04]

    assert Consent.allows?(method, 6_500, "EUR", today) == :ok
    assert Consent.allows?(method, 6_501, "EUR", today) == {:error, :consent_limit_exceeded}
    assert Consent.allows?(method, 100, "GBP", today) == {:error, :consent_currency_mismatch}

    assert Consent.allows?(%{method | status: "revoked"}, 100, "EUR", today) ==
             {:error, :payment_method_inactive}

    assert Consent.allows?(method, 100, "EUR", ~D[2027-03-01]) ==
             {:error, :payment_method_expired}
  end
end
