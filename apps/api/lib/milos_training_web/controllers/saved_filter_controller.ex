defmodule MilosTrainingWeb.SavedFilterController do
  @moduledoc "A person's remembered and named filters per list surface (ADR-151)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.SavedFilters
  alias MilosTrainingWeb.Schemas.SavedFilters, as: Schemas
  alias OpenApiSpex.{MediaType, Parameter, RequestBody}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  @surface %Parameter{name: :surface, in: :path, required: true, schema: Schemas.surface()}

  operation(:show,
    summary: "Your last-used and saved filters of one list surface",
    parameters: [@surface],
    responses: [ok: {"Filters", "application/json", Schemas.filters()}]
  )

  def show(conn, %{"surface" => surface}) do
    with {:ok, filters} <- SavedFilters.get(conn.assigns.user_context, surface) do
      json(conn, filters)
    end
  end

  operation(:remember,
    summary: "Remember the filter you just used on a surface",
    parameters: [@surface],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.remember_request()}}
    },
    responses: [ok: {"Filters", "application/json", Schemas.filters()}]
  )

  def remember(conn, %{"surface" => surface}) do
    with {:ok, filters} <-
           SavedFilters.remember(conn.assigns.user_context, surface, conn.body_params["params"]) do
      json(conn, filters)
    end
  end

  operation(:save,
    summary: "Save a named filter combination (same name replaces)",
    parameters: [@surface],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: Schemas.save_request()}}
    },
    responses: [ok: {"Filters", "application/json", Schemas.filters()}]
  )

  def save(conn, %{"surface" => surface}) do
    with {:ok, filters} <-
           SavedFilters.save(
             conn.assigns.user_context,
             surface,
             conn.body_params["name"],
             conn.body_params["params"]
           ) do
      json(conn, filters)
    end
  end

  operation(:delete,
    summary: "Delete a saved filter",
    parameters: [
      @surface,
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %OpenApiSpex.Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Filters", "application/json", Schemas.filters()}]
  )

  def delete(conn, %{"surface" => surface, "id" => id}) do
    with {:ok, filters} <- SavedFilters.delete(conn.assigns.user_context, surface, id) do
      json(conn, filters)
    end
  end
end
