defmodule Palee.Setup.Domain.RecipePlan do
  @moduledoc """
  What applying a recipe would change (CP-H2, ADR-255): a pure comparison of
  a `Recipe` with a snapshot of the business. The same plan is the preview
  (dry run) and the work list of an apply, so applying twice changes nothing
  the second time: everything already in place is `unchanged`.

  The snapshot (built by the `BusinessConfigurator` port):

      %{
        locale: "el",
        provider_kind: "gym",
        settings: %{"scheduling.default_capacity" => 12, ...},
        class_type_names: ["wod", ...],          # normalized, see `normalize_name/1`
        package_codes: ["setup_unlimited", ...],
        role_grants: %{"front_desk" => ["manage_billing"]},
        documents: :unsupported | ["health_certificate", ...]
      }

  Rules:

    * a setting changes when its value differs (lists compare as sets);
      `trials.conversion_package_id` names a recipe package by code and is
      only set while the box has none (it never replaces the owner's choice);
    * a class type is created when no class type has its name (in the
      business's language); a package when no package has its code;
    * role grants are only ever added;
    * documents are `manual` while the business cannot hold templates.

  Each change is a JSON-friendly map: `area`, `key`, `action` (`set`,
  `create`, `add`, `manual`), `from`, `to`, `name` and, for creations, the
  `attrs` to create with.
  """

  alias Palee.Setup.Domain.{Recipe, SettingsCatalog}

  @conversion_key "trials.conversion_package_id"

  @doc "`%{recipe, version, changes, manual, unchanged}` for `recipe` over `snapshot`."
  def build(%Recipe{} = recipe, %{} = snapshot) do
    locale = Map.get(snapshot, :locale)

    entries =
      [provider(recipe, snapshot)] ++
        Enum.map(recipe.packages, &package(&1, snapshot, locale)) ++
        Enum.map(recipe.class_types, &class_type(&1, snapshot, locale)) ++
        settings(recipe, snapshot) ++
        role_grants(recipe, snapshot) ++
        Enum.map(recipe.documents, &document(&1, snapshot, locale))

    {unchanged, rest} = Enum.split_with(entries, &match?({:unchanged, _key}, &1))
    {manual, changes} = Enum.split_with(rest, &(&1.action == "manual"))

    %{
      recipe: recipe.key,
      version: recipe.version,
      changes: changes,
      manual: manual,
      unchanged: unchanged |> Enum.map(&elem(&1, 1)) |> Enum.sort()
    }
  end

  @doc "Whether the plan has nothing left to apply."
  def empty?(%{changes: changes}), do: changes == []

  @doc "How class type names are compared: trimmed and case-insensitive."
  def normalize_name(name) when is_binary(name), do: name |> String.trim() |> String.downcase()

  defp provider(%Recipe{provider_kind: kind}, snapshot) do
    current = Map.get(snapshot, :provider_kind)

    if is_nil(kind) or current == kind,
      do: {:unchanged, "provider.kind"},
      else: %{
        area: "provider",
        key: "provider.kind",
        action: "set",
        from: current,
        to: kind,
        name: nil,
        advanced: SettingsCatalog.advanced?("provider.kind")
      }
  end

  defp package(package, snapshot, locale) do
    if package.code in Map.get(snapshot, :package_codes, []) do
      {:unchanged, "package." <> package.code}
    else
      name = Recipe.localized(package.names, locale)

      %{
        area: "package",
        key: "package." <> package.code,
        action: "create",
        from: nil,
        to: package.base_price_cents,
        name: name,
        attrs: %{
          code: package.code,
          name: name,
          package_type: package.package_type,
          billing_period: package.billing_period,
          base_price_cents: package.base_price_cents,
          fields: package.fields
        }
      }
    end
  end

  defp class_type(class_type, snapshot, locale) do
    name = Recipe.localized(class_type.names, locale)
    existing = Map.get(snapshot, :class_type_names, [])

    if normalize_name(name) in existing do
      {:unchanged, "class_type." <> class_type.slug}
    else
      %{
        area: "class_type",
        key: "class_type." <> class_type.slug,
        action: "create",
        from: nil,
        to: name,
        name: name,
        attrs:
          %{name: name, kind: Map.get(class_type, :kind, "class")}
          |> put_present(:level, Map.get(class_type, :level))
          |> put_present(:audiences, Map.get(class_type, :audiences))
      }
    end
  end

  defp settings(%Recipe{settings: settings}, snapshot) do
    current = Map.get(snapshot, :settings, %{})

    settings
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, target} -> setting(key, target, Map.get(current, key)) end)
  end

  defp setting(@conversion_key = key, code, current) do
    if is_nil(code) or not is_nil(current),
      do: {:unchanged, key},
      else: setting_change(key, current, code)
  end

  defp setting(key, target, current) do
    if same?(current, target), do: {:unchanged, key}, else: setting_change(key, current, target)
  end

  defp setting_change(key, from, to) do
    %{
      area: "setting",
      key: key,
      action: "set",
      from: from,
      to: to,
      name: nil,
      advanced: SettingsCatalog.advanced?(key)
    }
  end

  defp role_grants(%Recipe{role_grants: grants}, snapshot) do
    current = Map.get(snapshot, :role_grants, %{})

    grants
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {role, capabilities} ->
      had = current |> Map.get(role, []) |> Enum.sort()
      wanted = (had ++ capabilities) |> Enum.uniq() |> Enum.sort()

      if wanted == had,
        do: {:unchanged, "access.role_grants." <> role},
        else: %{
          area: "role_grant",
          key: "access.role_grants." <> role,
          action: "add",
          from: had,
          to: wanted,
          name: role,
          advanced: true
        }
    end)
  end

  defp document(document, snapshot, locale) do
    name = Recipe.localized(document.names, locale)

    case Map.get(snapshot, :documents, :unsupported) do
      existing when is_list(existing) ->
        if document.key in existing,
          do: {:unchanged, "document." <> document.key},
          else: %{
            area: "document",
            key: "document." <> document.key,
            action: "create",
            from: nil,
            to: name,
            name: name,
            attrs: %{key: document.key, name: name}
          }

      _unsupported ->
        %{
          area: "document",
          key: "document." <> document.key,
          action: "manual",
          from: nil,
          to: name,
          name: name
        }
    end
  end

  defp same?(current, target) when is_list(current) and is_list(target),
    do: Enum.sort(current) == Enum.sort(target)

  defp same?(current, target), do: current == target

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
