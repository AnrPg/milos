defmodule MilosTrainingWeb.PRController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    CreatePR,
    DeletePR,
    GetPRHistory,
    ListUserPRs,
    SharePR,
    UpdatePR
  }

  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

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
    beaten_on: %Schema{type: :string, format: :date}
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
    current_user = Guardian.Plug.current_resource(conn)
    opts = if params["q"], do: [query: params["q"]], else: []
    {:ok, prs} = ListUserPRs.call(current_user.id, opts)
    json(conn, %{prs: prs})
  end

  operation(:create,
    summary: "Create a PR record",
    request_body:
      {"PR params", "application/json",
       %Schema{
         type: :object,
         required: [:name, :current_score, :unit, :beaten_on],
         properties: @pr_fields
       }},
    responses: [
      created: {"PR", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, pr} <- CreatePR.call(current_user.id, params) do
      conn
      |> put_status(:created)
      |> json(%{pr: pr})
    end
  end

  operation(:update,
    summary: "Update a PR record",
    parameters: [@id_param],
    request_body:
      {"PR params", "application/json",
       %Schema{type: :object, properties: @pr_fields}},
    responses: [
      ok: {"PR", "application/json", %Schema{type: :object}},
      not_found: {"Error", "application/json", %Schema{type: :object}},
      unprocessable_entity: {"Error", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, pr} <- UpdatePR.call(id, current_user.id, params) do
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
    current_user = Guardian.Plug.current_resource(conn)

    with :ok <- DeletePR.call(id, current_user.id) do
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
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, entries} <- GetPRHistory.call(id, current_user.id) do
      json(conn, %{history: entries})
    end
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
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, result} <- SharePR.call(id, current_user.id) do
      json(conn, result)
    end
  end
end
