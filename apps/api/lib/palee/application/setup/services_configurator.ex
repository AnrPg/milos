defmodule Palee.Application.Setup.ServicesConfigurator do
  @moduledoc """
  The `Setup.Ports.BusinessConfigurator` adapter over Palee's own services
  (ADR-255). It reads each context through its public API and writes every
  change through the use case a staff screen would call, so validation,
  permissions and side rules stay in one place:

    * scheduling, finance, gamification and workout settings: the same
      writes as `PATCH /admin/settings` (`UpdateAdminSettings`);
    * check-in rules: `UpdateCheckInRules`; community: `Community`;
    * trial visitors: `Application.Trials.update_policy/2`;
    * the provider kind and role grants: `Organizations` (owner only);
    * class types: `CreateClassType`; packages: `CreateFinancePackage`.

  Document templates do not exist yet in this release, so the snapshot says
  `documents: :unsupported` and the plan lists them as manual steps.
  """

  @behaviour Palee.Setup.Ports.BusinessConfigurator

  alias Palee.{
    Community,
    Facility,
    Finance,
    Fiscal,
    Gamification,
    Organizations,
    Scheduling,
    Trials
  }

  alias Palee.Application.{
    BroadcastUserSync,
    CreateClassType,
    CreateFinancePackage,
    ListClassTypes,
    TenantStaffRecipients,
    UpdateCheckInRules
  }

  alias Palee.Application.Trials, as: TrialUseCases
  alias Palee.Setup.Domain.{RecipePlan, SettingsCatalog}

  @conversion_key "trials.conversion_package_id"

  @impl true
  def snapshot(context) do
    with {:ok, grants} <- Organizations.get_role_grants(context),
         {:ok, class_types} <- ListClassTypes.call(context, include_archived: true) do
      packages = Finance.list_packages(context)

      {:ok,
       %{
         locale: locale(context),
         currency: currency(context),
         provider_kind: Organizations.get_provider_kind(context),
         settings: settings(context),
         class_type_names: Enum.map(class_types, &RecipePlan.normalize_name(&1.name)),
         package_codes: packages |> Enum.map(& &1.code) |> Enum.reject(&is_nil/1),
         packages_by_code: Map.new(packages, &{&1.code, &1.id}),
         role_grants: grants,
         documents: :unsupported
       }}
    end
  end

  defp locale(context) do
    case Organizations.get_organization_settings(context.organization_id) do
      %{default_locale: locale} when is_binary(locale) -> locale
      _none -> "en"
    end
  end

  defp currency(context) do
    case Fiscal.identity_status(context) do
      %{profile: %{currency: currency}} when is_binary(currency) -> currency
      _none -> "EUR"
    end
  end

  # The current value of every setting a recipe may set, by catalog key.
  defp settings(context) do
    sections = %{
      "scheduling" => Scheduling.get_settings(context),
      "finance" => Finance.get_finance_settings(context),
      "gamification" => Gamification.with_tenant_context(context, &Gamification.get_settings/0),
      "workouts" => Organizations.get_workout_settings(context),
      "check_in" => Facility.check_in_rules(context),
      "community" => Community.community_settings(context),
      "trials" => Trials.policy(context)
    }

    SettingsCatalog.all()
    |> Enum.filter(& &1.set_by_recipe)
    |> Enum.flat_map(fn %{key: key, section: section, field: field} ->
      case Map.fetch(sections, section) do
        {:ok, values} -> [{key, field_value(values, field)}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp field_value(values, field) when is_map(values),
    do: Map.get(values, String.to_existing_atom(field))

  defp field_value(_values, _field), do: nil

  # ── Applying one change ────────────────────────────────────────────────

  @impl true
  def apply_change(context, %{area: "provider", to: kind}),
    do: ok(Organizations.put_provider_kind(context, kind))

  def apply_change(context, %{area: "package", attrs: attrs}) do
    params = %{
      code: attrs.code,
      name: attrs.name,
      package_type: attrs.package_type,
      billing_period: attrs.billing_period,
      base_price_cents: attrs.base_price_cents,
      currency: currency(context),
      params: %{
        "entitlement_version" => 2,
        "package_type" => attrs.package_type,
        "fields" => attrs.fields
      }
    }

    ok(CreateFinancePackage.call(context, params))
  end

  def apply_change(context, %{area: "class_type", attrs: attrs}),
    do: ok(CreateClassType.call(context, attrs))

  def apply_change(context, %{area: "role_grant", name: role, to: capabilities}),
    do: ok(Organizations.set_role_grants(context, role, capabilities))

  def apply_change(context, %{area: "setting", key: @conversion_key, to: code}) do
    case context |> Finance.list_packages() |> Enum.find(&(&1.code == code)) do
      nil -> {:error, :package_not_found}
      package -> ok(TrialUseCases.update_policy(context, %{conversion_package_id: package.id}))
    end
  end

  def apply_change(context, %{area: "setting", key: key, to: value}) do
    {section, field} = SettingsCatalog.split(key)
    write(context, section, %{String.to_existing_atom(field) => value})
  end

  def apply_change(_context, %{action: "manual"}), do: :ok
  def apply_change(_context, _change), do: {:error, :unsupported_change}

  defp write(context, "scheduling", params), do: ok(Scheduling.update_settings(context, params))

  defp write(context, "finance", params),
    do: ok(Finance.update_finance_settings(context, params))

  defp write(context, "gamification", params) do
    context
    |> Gamification.with_tenant_context(fn -> Gamification.update_settings(params) end)
    |> ok()
  end

  defp write(context, "workouts", params),
    do: ok(Organizations.update_workout_settings(context, params))

  defp write(context, "check_in", params), do: ok(UpdateCheckInRules.call(context, params))

  defp write(context, "community", params),
    do: ok(Community.put_community_settings(context, params))

  defp write(context, "trials", params), do: ok(TrialUseCases.update_policy(context, params))
  defp write(_context, _section, _params), do: {:error, :unsupported_change}

  defp ok({:ok, _value}), do: :ok
  defp ok(:ok), do: :ok
  defp ok({:error, _reason} = error), do: error

  @impl true
  def after_apply(context) do
    # Like a save of the settings screen: staff devices reload what changed.
    admin_ids = TenantStaffRecipients.user_ids(context)
    BroadcastUserSync.for_users(admin_ids, ["admin_settings"], reason: "setup_recipe_applied")
    :ok
  end
end
