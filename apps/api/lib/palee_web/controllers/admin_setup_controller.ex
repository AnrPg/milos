defmodule PaleeWeb.AdminSetupController do
  @moduledoc """
  Staff › Ρυθμίσεις (ADR-255): the settings catalog with the «Προχωρημένα»
  flag per setting (CP-H1) and the setup recipes (CP-H2): list, preview
  (dry run) and apply (owner only).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Setup.SetupRecipes
  alias PaleeWeb.Schemas.Setup, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Setup"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @key %Parameter{
    name: :key,
    in: :path,
    required: true,
    schema: %Schema{type: :string, maxLength: 60}
  }

  @error %Schema{
    type: :object,
    properties: %{
      code: %Schema{type: :string},
      error: %Schema{type: :string},
      step: %Schema{type: :string}
    },
    required: [:code, :error]
  }

  operation(:settings,
    summary: "Every business setting with its level (basic or under «Προχωρημένα»)",
    description:
      "CP-H1: the web shows the settings with `advanced: false` and keeps the rest under " <>
        "«Προχωρημένα», closed by default. `verdict` says why (derive: the app or a recipe sets it; " <>
        "remove: not shown to owners).",
    responses: [ok: {"Settings catalog", "application/json", S.settings_catalog()}]
  )

  def settings(conn, _params) do
    with {:ok, catalog} <- SetupRecipes.settings_catalog(conn.assigns.tenant_context) do
      json(conn, catalog)
    end
  end

  operation(:recipes,
    summary: "Setup recipes per kind of box, and the recipes this business applied",
    responses: [ok: {"Recipes", "application/json", S.recipes()}]
  )

  def recipes(conn, _params) do
    with {:ok, recipes} <- SetupRecipes.list(conn.assigns.tenant_context) do
      json(conn, recipes)
    end
  end

  operation(:preview,
    summary: "What applying a recipe would change now (dry run; nothing is saved)",
    parameters: [@key],
    responses: [
      ok: {"Plan", "application/json", S.plan()},
      not_found: {"No such recipe", "application/json", @error}
    ]
  )

  def preview(conn, %{key: key}) do
    with {:ok, plan} <- SetupRecipes.preview(conn.assigns.tenant_context, key) do
      json(conn, plan)
    end
  end

  operation(:apply_recipe,
    summary: "Apply a recipe (owner only); applying it again changes nothing",
    description:
      "Creates the recipe's subscription packages and class types that are missing and sets its " <>
        "settings through the same services as the settings screens, in one transaction, then " <>
        "records which recipe was applied, when and by whom. Documents are listed in `manual`.",
    parameters: [@key],
    responses: [
      ok: {"Applied", "application/json", S.applied()},
      forbidden: {"Not the owner", "application/json", @error},
      not_found: {"No such recipe", "application/json", @error},
      unprocessable_entity: {"A step failed; nothing changed", "application/json", @error}
    ]
  )

  def apply_recipe(conn, %{key: key}) do
    with {:ok, result} <- SetupRecipes.apply_recipe(conn.assigns.tenant_context, key) do
      json(conn, result)
    end
  end
end
