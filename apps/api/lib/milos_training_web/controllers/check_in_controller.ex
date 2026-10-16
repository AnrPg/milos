defmodule MilosTrainingWeb.CheckInController do
  @moduledoc "Πώς νιώθω check-ins of the current user (ADR-140 §2)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{DeleteMyCheckIn, ListMyCheckIns, SubmitCheckIn}
  alias MilosTrainingWeb.Schemas.FeedbackWellbeing
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Wellbeing"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, [json_render_error_v2: true] when action in [:create])

  operation(:index,
    summary: "The current user's Πώς νιώθω timeline",
    parameters: [
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time"}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time"}
      }
    ],
    responses: [
      ok: {"Questions and submissions", "application/json", FeedbackWellbeing.check_in_timeline()}
    ]
  )

  def index(conn, params) do
    with {:ok, payload} <- ListMyCheckIns.call(conn.assigns.user_context, params) do
      json(conn, payload)
    end
  end

  operation(:create,
    summary: "Submit a Πώς νιώθω check-in (a new timestamped entry)",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: FeedbackWellbeing.check_in_request()}}
    },
    responses: [created: {"Check-in", "application/json", FeedbackWellbeing.check_in_response()}]
  )

  def create(conn, _params) do
    with {:ok, check_in} <- SubmitCheckIn.call(conn.assigns.user_context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{check_in: check_in})
    end
  end

  operation(:delete,
    summary: "Delete one of the current user's check-ins",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [no_content: "Deleted"]
  )

  def delete(conn, %{"id" => id}) do
    with :ok <- DeleteMyCheckIn.call(conn.assigns.user_context, id) do
      send_resp(conn, :no_content, "")
    end
  end
end
