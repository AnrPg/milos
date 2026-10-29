defmodule Palee.Payments.Domain.PackageSaleTest do
  use ExUnit.Case, async: true

  alias Palee.Payments.Domain.PackageSale

  @connected %{available: true, options: %{}}
  @not_connected %{available: false, options: %{}}
  @pt_off %{available: true, options: %{"purposes" => %{"personal_training" => false}}}

  defp package(attrs) do
    Map.merge(
      %{
        id: "p1",
        active: true,
        package_type: "membership",
        base_price_cents: 6_000,
        sold_online: true,
        sold_online_chosen_at: nil
      },
      Map.new(attrs)
    )
  end

  describe "purpose/1 (ADR-260)" do
    test "maps each package type to its «Τι πληρώνεται online» switch" do
      assert PackageSale.purpose(%{package_type: "pt_pack"}) == "personal_training"
      assert PackageSale.purpose(%{package_type: "drop_in"}) == "drop_in"
      assert PackageSale.purpose(%{package_type: "trial"}) == "drop_in"
      assert PackageSale.purpose(%{package_type: "membership"}) == "packages"
    end
  end

  describe "visibility/2" do
    test "a paid package sold online with a provider is visible" do
      assert PackageSale.visibility(package([]), @connected) == "visible"
    end

    test "says why a package is not visible, in order" do
      assert PackageSale.visibility(package(active: false, base_price_cents: 0), @connected) ==
               "inactive"

      assert PackageSale.visibility(package(base_price_cents: 0, sold_online: false), @connected) ==
               "free"

      assert PackageSale.visibility(package(sold_online: false), @connected) == "off"

      assert PackageSale.visibility(package(package_type: "pt_pack"), @pt_off) == "purpose_off"
      assert PackageSale.visibility(package([]), @not_connected) == "no_provider"
    end

    test "a switched-off purpose matters only once a provider is connected" do
      offer = %{@pt_off | available: false}
      assert PackageSale.visibility(package(package_type: "pt_pack"), offer) == "no_provider"
    end

    test "listed?/2: the package page shows visible and not-yet-buyable packages" do
      assert PackageSale.listed?(package([]), @connected)
      assert PackageSale.listed?(package([]), @not_connected)
      refute PackageSale.listed?(package(package_type: "pt_pack"), @pt_off)
      refute PackageSale.listed?(package(sold_online: false), @connected)
    end
  end

  describe "opens?/2 and default_on?/2 (ADR-271)" do
    test "opens active paid packages whose purpose is on and whose owner never chose" do
      assert PackageSale.opens?(package(sold_online: false), @connected)
      refute PackageSale.opens?(package(base_price_cents: 0), @connected)
      refute PackageSale.opens?(package(active: false), @connected)
      refute PackageSale.opens?(package(package_type: "pt_pack"), @pt_off)

      refute PackageSale.opens?(
               package(sold_online: false, sold_online_chosen_at: ~U[2027-01-01 00:00:00Z]),
               @connected
             )
    end

    test "a new package starts on only while online payments work" do
      assert PackageSale.default_on?(package(sold_online: false), @connected)
      refute PackageSale.default_on?(package(sold_online: false), @not_connected)
    end
  end
end
