defmodule MilosTraining.Infrastructure.Localization.GettextAdapterTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Localization

  test "renders notification copy in the requested locale and interpolates authored values" do
    assert Localization.translate("el", "Message from %{nickname}", %{nickname: "Νίκη"}) ==
             "Μήνυμα από Νίκη"

    assert Localization.translate("ar", "Booking approved") != "Booking approved"
  end

  test "normalizes the persisted Portuguese locale for Gettext" do
    assert Localization.translate("pt-PT", "Booking approved") == "Reserva aprovada"
  end

  test "uses an explicit domain for calendar and sharing presentation" do
    assert Localization.translate("el", "Assigned workout", %{}, "calendar") ==
             "Ανατεθειμένη προπόνηση"

    assert Localization.translate("ar", "kilograms", %{}, "sharing") == "كيلوغرام"
  end
end
