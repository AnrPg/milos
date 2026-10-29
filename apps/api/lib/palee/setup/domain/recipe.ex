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
