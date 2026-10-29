defmodule Palee.Setup.Domain.RecipesTest do
  @moduledoc "ADR-255: every recipe only sets what the catalog allows, and names exist in English and Greek."

  use ExUnit.Case, async: true

  alias Palee.Finance.Domain.{PackageCode, PackageType}
  alias Palee.Organizations.Domain.AccessPolicy
  alias Palee.Setup.Domain.{Recipe, Recipes, SettingsCatalog}

  @box_types ~w(crossfit_box functional_hyrox personal_training_studio yoga_pilates_studio
                martial_arts_school open_gym independent_coach)

  test "one recipe per kind of box, with unique keys" do
    assert Recipes.keys() == @box_types
    assert {:ok, %Recipe{key: "crossfit_box"}} = Recipes.fetch("crossfit_box")
    assert {:error, :recipe_not_found} = Recipes.fetch("bowling_alley")
    assert {:error, :recipe_not_found} = Recipes.fetch(nil)
  end

  describe "with_prices/2 (the owner's prices from the preview, mockup s10 A)" do
    setup do
      {:ok, recipe} = Recipes.fetch("crossfit_box")
      %{recipe: recipe}
    end

    test "replaces the prices of the named packages only", %{recipe: recipe} do
      assert {:ok, priced} = Recipe.with_prices(recipe, %{"setup_unlimited" => 7_500})
      prices = Map.new(priced.packages, &{&1.code, &1.base_price_cents})
      assert prices["setup_unlimited"] == 7_500

      for package <- recipe.packages, package.code != "setup_unlimited" do
        assert prices[package.code] == package.base_price_cents
      end
    end

    test "keeps the recipe without prices", %{recipe: recipe} do
      assert {:ok, ^recipe} = Recipe.with_prices(recipe, nil)
      assert {:ok, ^recipe} = Recipe.with_prices(recipe, %{})
    end

    test "refuses unknown codes and prices that are not whole non-negative cents", %{
      recipe: recipe
    } do
      for prices <- [
            %{"setup_bowling" => 100},
            %{"setup_unlimited" => -1},
            %{"setup_unlimited" => 12.5},
            %{"setup_unlimited" => "80"},
            %{"setup_unlimited" => 10_000_001},
            ["setup_unlimited"]
          ] do
        assert {:error, :invalid_recipe_prices} = Recipe.with_prices(recipe, prices)
      end
    end
  end

  for recipe <- Palee.Setup.Domain.Recipes.all() do
    @recipe recipe

    describe "#{recipe.key}" do
      test "has a positive version and names and summaries in English and Greek" do
        assert @recipe.version > 0

        for texts <- [@recipe.names, @recipe.summaries] do
          assert is_binary(texts["en"]) and texts["en"] != ""
          assert is_binary(texts["el"]) and texts["el"] != ""
        end
      end

      test "sets only settings the catalog lets a recipe set" do
        for {key, _value} <- @recipe.settings do
          assert SettingsCatalog.recipe_settable?(key), "#{key} is not recipe-settable"
          # The provider kind and role grants have their own recipe fields.
          {section, _field} = SettingsCatalog.split(key)
          refute section in ~w(provider access)
        end
      end

      test "a trial conversion names one of its own packages" do
        case @recipe.settings["trials.conversion_package_id"] do
          nil -> :ok
          code -> assert code in Enum.map(@recipe.packages, & &1.code)
        end
      end

      test "packages use known types, valid billing periods, normalized unique codes and cents" do
        codes = Enum.map(@recipe.packages, & &1.code)
        assert codes == Enum.uniq(codes)

        for package <- @recipe.packages do
          assert PackageCode.normalize(package.code) == package.code
          assert {:ok, type} = PackageType.fetch(package.package_type)
          assert package.billing_period in PackageType.billing_periods(type)
          assert is_integer(package.base_price_cents) and package.base_price_cents >= 0
          assert package.names["en"] && package.names["el"]
        end
      end

      test "class types have unique slugs and names in both languages" do
        slugs = Enum.map(@recipe.class_types, & &1.slug)
        assert slugs == Enum.uniq(slugs)

        for class_type <- @recipe.class_types,
            do: assert(class_type.names["en"] && class_type.names["el"])
      end

      test "role grants only unlock grantable capabilities" do
        grantable =
          Map.new(AccessPolicy.grantable(), fn {role, caps} ->
            {to_string(role), Enum.map(caps, &to_string/1)}
          end)

        for {role, capabilities} <- @recipe.role_grants do
          assert Map.has_key?(grantable, role)
          assert capabilities -- grantable[role] == []
        end
      end

      test "package modules are available modules" do
        for module <- Map.get(@recipe.settings, "finance.package_modules", []),
            do: assert(PackageType.module_available?(module))
      end
    end
  end

  test "Greek names never write PT for personal training (ontology §4.4)" do
    for recipe <- Recipes.all(),
        texts <-
          [recipe.names, recipe.summaries] ++
            Enum.map(recipe.packages, & &1.names) ++ Enum.map(recipe.class_types, & &1.names) do
      refute texts["el"] =~ ~r/\bPT\b/
    end
  end

  test "localized/2 picks Greek for Greek locales and English otherwise" do
    names = %{"en" => "Trial", "el" => "Δοκιμαστικό"}
    assert Recipe.localized(names, "el") == "Δοκιμαστικό"
    assert Recipe.localized(names, "el-GR") == "Δοκιμαστικό"
    assert Recipe.localized(names, "de") == "Trial"
    assert Recipe.localized(names, nil) == "Trial"
  end
end
