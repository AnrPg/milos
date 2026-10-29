defmodule Palee.Imports.Domain.ValuesTest do
  use ExUnit.Case, async: true

  alias Palee.Imports.Domain.Values

  test "emails" do
    assert {:ok, "maria@example.gr"} = Values.email("  Maria@Example.GR ")
    assert {:error, :invalid_email} = Values.email("maria@example")
    assert :blank = Values.email("")
  end

  test "phones keep a country code and match on the last 10 digits" do
    assert {:ok, "+306941234567"} = Values.phone("+30 694 123 4567")
    assert {:ok, "+306941234567"} = Values.phone("0030 6941234567")
    assert {:ok, "6941234567"} = Values.phone("694-123-4567")
    assert {:error, :invalid_phone} = Values.phone("123")

    keys = Enum.map(["+30 694 123 4567", "0030 6941234567", "6941234567"], &Values.phone_key/1)
    assert Enum.uniq(keys) == ["6941234567"]
    assert Values.phone_key("+1 (415) 555-0100") == Values.phone_key("415.555.0100")
  end

  test "money in EU and US formats" do
    assert {:ok, 123_456} = Values.money("1.234,56")
    assert {:ok, 123_456} = Values.money("1,234.56")
    assert {:ok, 4500} = Values.money("€45")
    assert {:ok, 4550} = Values.money("45,5 €")
    assert {:ok, 150_000} = Values.money("1.500")
    assert {:ok, 150_000} = Values.money("$1,500")
    assert {:ok, 123_456_789} = Values.money("1.234.567,89")
    assert {:ok, -1200} = Values.money("(12.00)")
    assert {:ok, -1200} = Values.money("-12")
    assert {:error, :invalid_amount} = Values.money("12.3456")
    assert {:error, :invalid_amount} = Values.money("abc")
  end

  test "roles, payment methods and statuses in English and Greek" do
    assert {:ok, "athlete"} = Values.role("Αθλητής")
    assert {:ok, "member"} = Values.role("Member")
    assert {:error, :invalid_role} = Values.role("coach")

    assert {:ok, "cash"} = Values.payment_method("Μετρητά")
    assert {:ok, "card_manual"} = Values.payment_method("Credit Card")
    assert {:ok, "bank_transfer"} = Values.payment_method("Bank transfer")
    assert {:ok, "other"} = Values.payment_method("voucher")

    assert {:ok, "active"} = Values.membership_status("Ενεργό")
    assert {:ok, "expired"} = Values.membership_status("Inactive")
    assert {:ok, "paused"} = Values.membership_status("On Hold")
    assert {:error, :invalid_status} = Values.membership_status("???")
  end

  test "text is trimmed and collapsed" do
    assert {:ok, "Maria Papadopoulou"} = Values.text("  Maria   Papadopoulou ")
    assert :blank = Values.text(" \t ")
  end
end
