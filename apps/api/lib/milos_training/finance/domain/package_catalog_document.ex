defmodule MilosTraining.Finance.Domain.PackageCatalogDocument do
  @moduledoc """
  Read-only description of package types, presets, locks and field
  specifications for package authoring clients (ADR-096).

  Clients render the package wizard and advanced settings from this document
  instead of duplicating presets or lock rules.
  """

  alias MilosTraining.Finance.Domain.{PackageCatalog, PackagePresets, PackageType}

  def build(enabled_modules) do
    enabled_modules = Enum.filter(enabled_modules || [], &PackageType.module_available?/1)

    %{
      version: MilosTraining.Finance.Domain.PackageContract.version(),
      implemented_phases: Enum.map(PackageCatalog.implemented_phases(), &Atom.to_string/1),
      modules:
        Enum.map(PackageType.modules(), fn module ->
          %{
            key: module.key,
            available: PackageType.available?(module),
            enabled: module.key in enabled_modules
          }
        end),
      sections: PackageCatalog.sections(),
      fields: Enum.map(PackageCatalog.fields(), &field_spec/1),
      types: Enum.map(PackageType.types(), &type_document(&1, enabled_modules))
    }
  end

  defp type_document(type, enabled_modules) do
    {:ok, preset} = PackagePresets.preset(type.key)

    %{
      key: type.key,
      available: PackageType.available?(type),
      enabled: is_nil(type.module) or type.module in enabled_modules,
      billing_model: type.billing_model,
      billing_periods: PackageType.billing_periods(type),
      default_billing_period: PackageType.default_billing_period(type),
      preset: preset,
      billing_period_overrides: PackagePresets.billing_period_overrides(type.key),
      locks:
        Enum.map(PackagePresets.locks(type.key), fn {path, value, reason} ->
          %{path: path, field: PackagePresets.lock_field(path), value: value, reason: reason}
        end)
    }
  end

  defp field_spec(spec) do
    spec
    |> Map.take([:key, :section, :options, :min, :max])
    |> Map.put(:kind, Atom.to_string(spec.kind))
    |> Map.put(:phase, Atom.to_string(spec.phase))
    |> Map.put(:available, PackageCatalog.available?(spec))
  end
end
