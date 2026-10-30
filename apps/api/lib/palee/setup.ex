defmodule Palee.Setup do
  @moduledoc """
  The Setup bounded context (CP-H1, CP-H2, ADR-255): how a business starts
  and how its settings are presented.

    * the settings catalog: every business setting with its verdict (basic,
      «Προχωρημένα», derived, removed from the screens);
    * setup recipes: declarative starting choices per kind of box, compared
      with the business (a dry-run plan) and applied through the existing
      services behind the `BusinessConfigurator` port;
    * the record of applied recipes.

  Setup owns only its record. Use cases that need permissions and other
  contexts live in `Palee.Application.Setup.*`.
  """

  alias Palee.Setup.Domain.{RecipePlan, Recipes, SettingsCatalog, TenantDataPolicy}
  alias Palee.Setup.RecipeApplicationStore

  @doc "The configured `Setup.Ports.BusinessConfigurator`."
  def configurator, do: Application.fetch_env!(:palee, :setup_business_configurator)

  # ── Settings catalog ────────────────────────────────────────────────────

  defdelegate settings_catalog(), to: SettingsCatalog, as: :all
  defdelegate advanced_settings(), to: SettingsCatalog, as: :advanced_keys
  defdelegate settings_counts(), to: SettingsCatalog, as: :counts

  # ── Recipes ─────────────────────────────────────────────────────────────

  defdelegate recipes(), to: Recipes, as: :all
  defdelegate fetch_recipe(key), to: Recipes, as: :fetch
  defdelegate plan(recipe, snapshot), to: RecipePlan, as: :build

  # ── Record ──────────────────────────────────────────────────────────────

  defdelegate transaction(context, fun), to: RecipeApplicationStore
  defdelegate record_application(context, attrs), to: RecipeApplicationStore, as: :insert
  def list_applications(context, limit \\ 20), do: RecipeApplicationStore.list(context, limit)

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
