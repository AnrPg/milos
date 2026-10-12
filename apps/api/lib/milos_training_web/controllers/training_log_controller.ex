defmodule MilosTrainingWeb.TrainingLogController do
  @moduledoc """
  Member/athlete training log for workouts that never ran as executions
  (ADR-118). Tenant-scoped: every route requires `conn.assigns.tenant_context`.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    ListTrainingLogEntries,
    ListTrainingLogSources,
    LogTrainingEntry,
    UpdateTrainingLogEntry,
    VoidTrainingLogEntry
  }

  alias MilosTrainingWeb.Schemas.TrainingLog
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Training Log"])
  security([%{"bearerAuth" => []}])

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    [json_render_error_v2: true] when action in [:create, :update, :void]
  )

  @id_param %Parameter{
    name: :id,
    in: :path,
    description: "Training log entry ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @error {"Error", "application/json", %Schema{type: :object}}

  operation(:index,
    summary: "List the current user's training log entries in this organization",
    responses: [ok: {"Training log entries", "application/json", TrainingLog.entry_collection()}]
  )

  def index(conn, _params) do
    with {:ok, entries} <- ListTrainingLogEntries.call(tenant_context(conn), actor(conn)) do
      json(conn, %{entries: entries})
    end
  end

  operation(:sources,
    summary: "List classes, assignments, and library workouts that can be logged",
    responses: [ok: {"Loggable sources", "application/json", TrainingLog.sources_response()}]
  )

  def sources(conn, _params) do
    with {:ok, sources} <- ListTrainingLogSources.call(tenant_context(conn), actor(conn)) do
      json(conn, sources)
    end
  end

  operation(:show,
    summary: "Get one of the current user's training log entries",
    parameters: [@id_param],
    responses: [
      ok: {"Training log entry", "application/json", TrainingLog.entry_response()},
      not_found: @error
    ]
  )

  def show(conn, params) do
    id = param_id(params)

    with {:ok, entry} <- ListTrainingLogEntries.get(tenant_context(conn), actor(conn), id) do
      json(conn, %{entry: entry})
    end
  end

  operation(:create,
    summary: "Log a class, assigned, library, or freeform workout",
    description:
      "Idempotent per `idempotency_key`: a replay returns the original entry with 200, " <>
        "before source authorization is re-evaluated (ADR-120). Reusing a key for a " <>
        "different source returns 409 `idempotency_key_conflict`. " <>
        "Logging feeds the same durable completion projection as workout executions.",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: TrainingLog.create_request()}}
    },
    responses: [
      created: {"Training log entry", "application/json", TrainingLog.entry_response()},
      ok: {"Replayed training log entry", "application/json", TrainingLog.entry_response()},
      forbidden: @error,
      not_found: @error,
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def create(conn, _params) do
    with {:ok, entry, outcome} <-
           LogTrainingEntry.call(tenant_context(conn), actor(conn), conn.body_params) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(%{entry: entry})
    end
  end

  operation(:update,
    summary: "Edit the performed details of a training log entry",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: TrainingLog.update_request()}}
    },
    responses: [
      ok: {"Training log entry", "application/json", TrainingLog.entry_response()},
      not_found: @error,
      conflict: @error,
      unprocessable_entity: @error
    ]
  )

  def update(conn, params) do
    id = param_id(params)

    with {:ok, entry} <-
           UpdateTrainingLogEntry.call(tenant_context(conn), actor(conn), id, body_params(conn)) do
      json(conn, %{entry: entry})
    end
  end

  operation(:void,
    summary: "Void a training log entry (entries are never deleted)",
    parameters: [@id_param],
    request_body: %RequestBody{
      required: false,
      content: %{"application/json" => %MediaType{schema: TrainingLog.void_request()}}
    },
    responses: [
      ok: {"Training log entry", "application/json", TrainingLog.entry_response()},
      not_found: @error,
      conflict: @error
    ]
  )

  def void(conn, params) do
    id = param_id(params)

    with {:ok, entry} <-
           VoidTrainingLogEntry.call(
             tenant_context(conn),
             actor(conn),
             id,
             body_params(conn)
           ) do
      json(conn, %{entry: entry})
    end
  end

  defp param_id(params), do: params[:id] || params["id"]

  defp body_params(conn), do: Map.drop(conn.body_params, [:id, "id"])

  defp tenant_context(conn), do: conn.assigns[:tenant_context]
  defp actor(conn), do: Guardian.Plug.current_resource(conn)
end
