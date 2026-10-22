defmodule Palee.Organizations.Domain.TimeZonePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.TimeZonePolicy, as: Policy

  test "a known zone resolves; an unknown or never-set one falls back to the default" do
    assert Policy.resolve(%{timezone: "Europe/Berlin", timezone_source: "confirmed"}) ==
             "Europe/Berlin"

    assert Policy.resolve(%{timezone: "Europe/Berlin", timezone_source: "inferred"}) ==
             "Europe/Berlin"

    assert Policy.resolve(%{timezone: "UTC", timezone_source: nil}) == Policy.default_zone()

    assert Policy.resolve(%{timezone: "Not/AZone", timezone_source: "confirmed"}) ==
             Policy.default_zone()

    assert Policy.resolve(nil) == Policy.default_zone()
  end

  test "a guess never replaces a confirmed zone" do
    assert Policy.accept?(nil, "inferred")
    assert Policy.accept?("inferred", "inferred")
    refute Policy.accept?("confirmed", "inferred")
    assert Policy.accept?("confirmed", "confirmed")
    refute Policy.accept?(nil, "made_up")
  end

  test "inference takes the first known non-UTC candidate" do
    assert Policy.infer(["Europe/Athens", "Europe/Berlin"]) == "Europe/Athens"
    assert Policy.infer([nil, "Etc/UTC", "bogus", "America/New_York"]) == "America/New_York"
    assert Policy.infer([nil, "UTC"]) == nil
  end
end
