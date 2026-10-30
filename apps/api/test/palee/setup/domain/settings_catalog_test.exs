defmodule Palee.Setup.Domain.SettingsCatalogTest do
  @moduledoc "ADR-255 (CP-H1): one verdict per setting; advanced unless basic."

  use ExUnit.Case, async: true

  alias Palee.Setup.Domain.SettingsCatalog

  test "keys are unique and dotted" do
    keys = Enum.map(SettingsCatalog.all(), & &1.key)
    assert keys == Enum.uniq(keys)
    assert Enum.all?(keys, &(&1 =~ ~r/^[a-z_]+\.[a-z_]+$/))
  end

  test "every verdict is known and advanced means not basic" do
    for setting <- SettingsCatalog.all() do
      assert setting.verdict in SettingsCatalog.verdicts()
      assert setting.advanced == (setting.verdict != :basic)
      assert SettingsCatalog.advanced?(setting.key) == setting.advanced
    end
  end

  test "advanced_keys/0 is sorted and holds exactly the non-basic settings" do
    keys = SettingsCatalog.advanced_keys()
    assert keys == Enum.sort(keys)

    assert MapSet.new(keys) ==
             MapSet.new(for s <- SettingsCatalog.all(), s.verdict != :basic, do: s.key)

    assert "finance.subscription_grace_days" in keys
    refute "scheduling.default_capacity" in keys
  end

  test "an unknown key is advanced and not recipe-settable" do
    assert SettingsCatalog.advanced?("nothing.here")
    refute SettingsCatalog.recipe_settable?("nothing.here")
    assert SettingsCatalog.fetch("nothing.here") == :error
  end

  test "counts match the audit document's summary" do
    counts = SettingsCatalog.counts()
    assert Enum.sum(Map.values(counts)) == length(SettingsCatalog.all())

    audit = File.read!(Path.expand("../../../../../../docs/plans/v3-settings-audit.md", __DIR__))

    for {verdict, label} <- [basic: "Basic", advanced: "Advanced", derive: "Derive"] do
      assert audit =~ "| #{label} | #{counts[verdict]} |",
             "the audit summary must say #{counts[verdict]} for #{label}"
    end

    assert audit =~ "| Remove (UI) | #{counts.remove} |"
    assert audit =~ "| **Total business settings** | **#{length(SettingsCatalog.all())}** |"
  end

  test "settings recipes write are the ones the services accept" do
    settable = for s <- SettingsCatalog.all(), s.set_by_recipe, do: s.section

    assert Enum.uniq(settable) --
             ~w(provider access workouts finance scheduling gamification check_in community trials) ==
             []
  end
end
