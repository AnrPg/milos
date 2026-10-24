defmodule PaleeWeb.PRController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    CreatePR,
    DeletePR,
    EditPR,
    GetPRHistory,
    ListUserPRs,
    SharePR,
    UpdatePR
  }

  alias PaleeWeb.Schemas.JournalComments
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Pantheon"])
  security([%{"bearerAuth" => []}])

  @id_param %Parameter{
    name: :id,
    in: :path,
    description: "PR Record ID",
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  @pr_fields %{
    name: %Schema{type: :string},
    current_score: %Schema{type: :number},
    unit: %Schema{
      type: :string,
      enum: ["mins_secs", "reps", "sets", "kcals", "m", "kg"]
    },
    higher_is_better: %Schema{type: :boolean},
    beaten_on: %Schema{type: :string, format: :date},
    supporting_metrics: %Schema{
      type: :object,
      description:
        "Optional typed result context. Accepted keys: reps, sets, load_kg, duration_seconds, distance_m, calories, rounds, variation."
    },
    comments: JournalComments.inline_inputs()
  }

  operation(:index,
    summary: "List my PRs",
    parameters: [
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string}
      }
    ],
    responses: [ok: {"PRs", "application/json", %Schema{type: :object}}]
  )

  def index(conn, params) do
    opts = if params["q"], do: [query: params["q"]], else: []
    {:ok, prs} = ListUserPRs.call(conn.assigns.user_context, opts)
    json(conn, %{prs: prs})
  end

  operation(:create,
    summary: "Create a PR record",
    request_body:
      {"PR params", "application/json",
       %Schema{
         type: :object,
         required: [:name, :current_score, :unit, :beaten_on],
         properties:
           Map.put(@pr_fields, :organization_slug, %Schema{
             type: :string,
             nullable: true,
             description:
               "Gym the PR was achieved in (ADR-129). Must be one of the caller's active memberships; the gym's coaches can then read it. Omit for a personal PR."
           })
       }},
    responses: [
      created: {"PR", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, params) do
    with {:ok, pr} <- CreatePR.call(conn.assigns.user_context, params) do
      conn
      |> put_status(:created)
      |> json(%{pr: pr})
    end
  end

  operation(:update,
    summary: "Update a PR record",
    parameters: [@id_param],
    request_body:
      {"PR params", "application/json", %Schema{type: :object, properties: @pr_fields}},
    responses: [
      ok: {"PR", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with {:ok, pr} <- UpdatePR.call(conn.assigns.user_context, id, params) do
      json(conn, %{pr: pr})
    end
  end

  operation(:edit,
    summary: "Correct the current PR result without adding history",
    parameters: [@id_param],
    request_body:
      {"PR params", "application/json", %Schema{type: :object, properties: @pr_fields}},
    responses: [
      ok: {"PR", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def edit(conn, %{"id" => id} = params) do
    with {:ok, pr} <- EditPR.call(conn.assigns.user_context, id, params) do
      json(conn, %{pr: pr})
    end
  end

  operation(:delete,
    summary: "Delete a PR record",
    parameters: [@id_param],
    responses: [
      no_content: {"Deleted", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def delete(conn, %{"id" => id}) do
    with :ok <- DeletePR.call(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end

  operation(:history,
    summary: "Get score history for a PR",
    parameters: [@id_param],
    responses: [
      ok: {"PR History", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def history(conn, %{"id" => id}) do
    with {:ok, entries} <- GetPRHistory.call(conn.assigns.user_context, id) do
      json(conn, %{history: entries})
    end
  end

  operation(:all_history,
    summary: "Score history of all my PRs, oldest first (ADR-194)",
    responses: [
      ok:
        {"PR history", "application/json",
         %Schema{
           title: "PRHistoryList",
           type: :object,
           required: [:history],
           properties: %{
             history: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 required: [:id, :pr_record_id, :score, :beaten_on, :supporting_metrics],
                 properties: %{
                   id: %Schema{type: :string, format: :uuid},
                   pr_record_id: %Schema{type: :string, format: :uuid},
                   score: %Schema{type: :number},
                   beaten_on: %Schema{type: :string, format: :date},
                   supporting_metrics: %Schema{type: :object, additionalProperties: true},
                   inserted_at: %Schema{type: :string, format: :"date-time"}
                 }
               }
             }
           }
         }}
    ]
  )

  def all_history(conn, _params) do
    {:ok, entries} = GetPRHistory.all(conn.assigns.user_context)
    json(conn, %{history: entries})
  end

  operation(:share,
    summary: "Get a shareable text for a PR",
    parameters: [@id_param],
    responses: [
      ok: {"Share message", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def share(conn, %{"id" => id}) do
    with {:ok, result} <- SharePR.call(conn.assigns.user_context, id) do
      json(conn, result)
    end
  end
end
