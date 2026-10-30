defmodule Palee.Setup.Domain.Recipe do
  @moduledoc """
  A setup recipe (CP-H2, ADR-255): a declarative set of starting choices for
  one kind of box, across contexts. Nothing in it is code that runs: the
  plan (`RecipePlan`) compares it with what the business has, and the
  application layer applies the differences through the existing services.

    * `provider_kind` – how members see the business (ADR-162);
    * `settings` – `%{catalog key => value}`; only keys the
      `SettingsCatalog` marks `recipe: true`;
    * `class_types` – `%{slug, names, kind, level, audiences, credit_cost}`,
      created when no class type with the slug exists;
    * `packages` – subscription packages `%{code, names, package_type,
      billing_period, base_price_cents, fields}`, created when no package
      has the code; `fields` are package catalog values over the type preset.
      The package with `trial_conversion: true` becomes the trial's
      conversion package when the box has none;
    * `role_grants` – capabilities unlocked per role (ADR-099), added to
      what the box already unlocked, never taken away;
    * `documents` – documents the box should ask for (health certificate,
      terms); a placeholder until the business has document templates.

  Names come in English and Greek (`names: %{"en" => …, "el" => …}`); a
  business whose language is Greek gets the Greek ones.
  """

  @enforce_keys [:key, :version, :names, :summaries]
  defstruct [
    :key,
    :version,
    :names,
    :summaries,
    provider_kind: "gym",
    settings: %{},
    class_types: [],
    packages: [],
    role_grants: %{},
    documents: []
  ]

  @type t :: %__MODULE__{}

  # A price above 100,000.00 is a typo, not a subscription package.
  @max_price_cents 10_000_000

  @doc """
  The recipe with the owner's own prices for its packages: `prices` is
  `%{package code => cents}` from the preview (mockup s10 A, «Άλλαξε τιμές
  εδώ»). `{:ok, recipe}` or `{:error, :invalid_recipe_prices}` for a code
  the recipe does not have or a price that is not a whole, non-negative
  number of cents.
  """
  def with_prices(%__MODULE__{} = recipe, nil), do: {:ok, recipe}

  def with_prices(%__MODULE__{} = recipe, prices) when is_map(prices) do
    codes = MapSet.new(recipe.packages, & &1.code)

    valid? =
      Enum.all?(prices, fn {code, cents} ->
        MapSet.member?(codes, to_string(code)) and is_integer(cents) and cents >= 0 and
          cents <= @max_price_cents
      end)

    if valid? do
      prices = Map.new(prices, fn {code, cents} -> {to_string(code), cents} end)

      packages =
        Enum.map(recipe.packages, fn package ->
          %{package | base_price_cents: Map.get(prices, package.code, package.base_price_cents)}
        end)

      {:ok, %{recipe | packages: packages}}
    else
      {:error, :invalid_recipe_prices}
    end
  end

  def with_prices(%__MODULE__{}, _prices), do: {:error, :invalid_recipe_prices}

  @doc "The name in `locale` (\"el\" or English for anything else)."
  def localized(%{} = names, locale) do
    if locale_language(locale) == "el",
      do: Map.get(names, "el") || Map.fetch!(names, "en"),
      else: Map.fetch!(names, "en")
  end

  defp locale_language(locale) when is_binary(locale),
    do: locale |> String.split(["-", "_"]) |> hd() |> String.downcase()

  defp locale_language(_locale), do: "en"
end
