defmodule Palee.Application.Setup.SetupRecipes do
  @moduledoc """
  Staff use cases of the Setup context (CP-H1, CP-H2, ADR-255):

    * the settings catalog: every business setting with its level, so the
      web shows the basic ones and keeps the rest under «Προχωρημένα»;
    * the setup recipes, each with what it would set;
    * a preview: the dry-run plan of one recipe over the business as it is;
    * applying a recipe: owner only. The plan is rebuilt and applied in one
      transaction through the existing services (`BusinessConfigurator`),
      then recorded (recipe, version, who, when, what changed). Applying
      the same recipe again changes nothing.

  Everything needs `manage_settings`.
  """

  alias Palee.{Organizations, Setup}
  alias Palee.Setup.Domain.Recipe

  @history 20

  @doc "`%{settings, counts, advanced_settings}`."
  def settings_catalog(context) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings) do
      {:ok,
       %{
         settings: Enum.map(Setup.settings_catalog(), &present_setting/1),
         counts: Map.new(Setup.settings_counts(), fn {verdict, n} -> {to_string(verdict), n} end),
         advanced_settings: Setup.advanced_settings()
       }}
    end
  end

  @doc "`%{recipes, applications}`: every recipe and the business's applications."
  def list(context) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         {:ok, snapshot} <- Setup.configurator().snapshot(context) do
      {:ok,
       %{
         recipes: Enum.map(Setup.recipes(), &present_recipe(&1, snapshot.locale)),
         applications: Setup.list_applications(context, @history),
         can_apply: owner?(context)
       }}
    end
  end

  @doc "The dry-run plan of recipe `key` over the business as it is now."
  def preview(context, key) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         {:ok, recipe} <- Setup.fetch_recipe(key),
         {:ok, snapshot} <- Setup.configurator().snapshot(context) do
      {:ok, present_plan(Setup.plan(recipe, snapshot), recipe, snapshot.locale)}
    end
  end

  @doc """
  Applies recipe `key`: `%{plan, application}` where `plan` lists what was
  changed. Owner only (the provider kind and role grants are the owner's).
  """
  def apply_recipe(context, key, now \\ DateTime.utc_now()),
    do: apply_recipe_with_prices(context, key, nil, now)

  @doc """
  Like `apply_recipe/3`, with the owner's own prices for the recipe's
  packages (`%{code => cents}`), as changed in the preview.
  """
  def apply_recipe_with_prices(context, key, prices, now \\ DateTime.utc_now()) do
    with :ok <- Organizations.authorize_capability(context, :manage_settings),
         :ok <- owner(context),
         {:ok, recipe} <- Setup.fetch_recipe(key),
         {:ok, recipe} <- Recipe.with_prices(recipe, prices),
         {:ok, result} <- Setup.transaction(context, fn -> apply_plan(context, recipe, now) end) do
      Setup.configurator().after_apply(context)
      {:ok, result}
    end
  end

  defp apply_plan(context, recipe, now) do
    configurator = Setup.configurator()

    with {:ok, snapshot} <- configurator.snapshot(context),
         plan = Setup.plan(recipe, snapshot),
         :ok <- apply_changes(configurator, context, plan.changes),
         {:ok, application} <-
           Setup.record_application(context, %{
             recipe_key: recipe.key,
             recipe_version: recipe.version,
             applied_by_id: Map.get(context, :user_id),
             applied_at: now,
             changes: Enum.map(plan.changes, &stored_change/1),
             manual: Enum.map(plan.manual, &stored_change/1),
             change_count: length(plan.changes)
           }) do
      {:ok, %{plan: present_plan(plan, recipe, snapshot.locale), application: application}}
    end
  end

  defp apply_changes(configurator, context, changes) do
    Enum.reduce_while(changes, :ok, fn change, :ok ->
      case configurator.apply_change(context, change) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:recipe_step_failed, change.key, reason}}}
      end
    end)
  end

  defp owner(context), do: if(owner?(context), do: :ok, else: {:error, :recipe_owner_only})
  defp owner?(context), do: Organizations.any_role?(context, [:owner])

  # ── Presentation ───────────────────────────────────────────────────────

  defp present_setting(setting),
    do: %{setting | verdict: to_string(setting.verdict)}

  defp present_recipe(%Recipe{} = recipe, locale) do
    %{
      key: recipe.key,
      version: recipe.version,
      name: Recipe.localized(recipe.names, locale),
      summary: Recipe.localized(recipe.summaries, locale),
      names: recipe.names,
      summaries: recipe.summaries,
      provider_kind: recipe.provider_kind,
      settings:
        recipe.settings
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {key, value} ->
          %{key: key, value: value, advanced: Palee.Setup.Domain.SettingsCatalog.advanced?(key)}
        end),
      class_types: Enum.map(recipe.class_types, &Recipe.localized(&1.names, locale)),
      packages:
        Enum.map(recipe.packages, fn package ->
          %{
            code: package.code,
            name: Recipe.localized(package.names, locale),
            package_type: package.package_type,
            billing_period: package.billing_period,
            base_price_cents: package.base_price_cents
          }
        end),
      role_grants: recipe.role_grants,
      documents: Enum.map(recipe.documents, &Recipe.localized(&1.names, locale))
    }
  end

  defp present_plan(plan, recipe, locale) do
    %{
      recipe: plan.recipe,
      version: plan.version,
      name: Recipe.localized(recipe.names, locale),
      changes: Enum.map(plan.changes, &stored_change/1),
      manual: Enum.map(plan.manual, &stored_change/1),
      unchanged: plan.unchanged,
      change_count: length(plan.changes)
    }
  end

  defp stored_change(change) do
    %{
      area: change.area,
      key: change.key,
      action: change.action,
      from: change.from,
      to: change.to,
      name: change.name,
      advanced: Map.get(change, :advanced, false)
    }
  end
end
