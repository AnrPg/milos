defmodule PaleeWeb.AccountTrainingController do
  @moduledoc """
  The account-level training read model (ADR-150, ADR-162): history,
  Πρόοδος and the Vault across every provider, each item with its source.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{GetAccountHistory, GetAccountProgress, GetAccountVault}
  alias PaleeWeb.Schemas.CrossProvider
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Training Log"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @sources %Parameter{
    name: :sources,
    in: :query,
    required: false,
    description: "Comma-separated provider ids, `freeform`, `device` (all when absent)",
    schema: %Schema{type: :string}
  }
  @date_from %Parameter{
    name: :date_from,
    in: :query,
    required: false,
    schema: %Schema{type: :string, format: :date}
  }
  @date_to %Parameter{
    name: :date_to,
    in: :query,
    required: false,
    schema: %Schema{type: :string, format: :date}
  }
  @exercise %Parameter{
    name: :exercise,
    in: :query,
    required: false,
    description: "An exercise name (matched by substring)",
    schema: %Schema{type: :string}
  }

  operation(:history,
    summary: "Your training log across every provider (workouts or booked classes)",
    parameters: [
      %Parameter{
        name: :kind,
        in: :query,
        schema: %Schema{type: :string, enum: ["workouts", "classes"], default: "workouts"}
      },
      %Parameter{name: :offset, in: :query, schema: %Schema{type: :integer, minimum: 0}},
      %Parameter{
        name: :limit,
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 50}
      },
      @sources,
      @date_from,
      @date_to
    ],
    responses: [ok: {"History page", "application/json", CrossProvider.history_page()}]
  )

  def history(conn, params) do
    with {:ok, page} <- GetAccountHistory.call(conn.assigns.user_context, query(params)) do
      json(conn, page)
    end
  end

  operation(:progress,
    summary: "Πρόοδος across every provider",
    parameters: [
      %Parameter{
        name: :range,
        in: :query,
        schema: %Schema{type: :string, enum: ["4w", "12w", "6m", "1y", "all"], default: "all"}
      },
      @sources,
      @exercise
    ],
    responses: [
      ok:
        {"Progress", "application/json",
         %Schema{
           title: "AccountProgressResponse",
           type: :object,
           required: [:progress],
           properties: %{progress: CrossProvider.progress_response()}
         }}
    ]
  )

  def progress(conn, params) do
    with {:ok, progress} <- GetAccountProgress.call(conn.assigns.user_context, query(params)) do
      json(conn, %{progress: progress})
    end
  end

  operation(:vault,
    summary: "The Vault across every provider: one trend per workout, every attempt labelled",
    parameters: [
      %Parameter{
        name: :disciplines,
        in: :query,
        required: false,
        description: "Comma-separated workout types",
        schema: %Schema{type: :string}
      },
      %Parameter{
        name: :benchmark,
        in: :query,
        required: false,
        description: "A benchmark slug such as `fran`",
        schema: %Schema{type: :string}
      },
      @exercise,
      @sources,
      @date_from,
      @date_to
    ],
    responses: [ok: {"Vault", "application/json", CrossProvider.vault_response()}]
  )

  def vault(conn, params) do
    with {:ok, vault} <- GetAccountVault.call(conn.assigns.user_context, query(params)) do
      json(conn, vault)
    end
  end

  defp query(params) do
    Map.new(params, fn
      {key, %Date{} = date} -> {to_string(key), Date.to_iso8601(date)}
      {key, value} -> {to_string(key), value}
    end)
  end
end
