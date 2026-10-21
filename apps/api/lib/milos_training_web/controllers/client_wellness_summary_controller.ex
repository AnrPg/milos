defmodule MilosTrainingWeb.ClientWellnessSummaryController do
  @moduledoc """
  A coach reads a client's weekly wellness summary (ADR-160): counts only,
  cravings (count and times) only with the client's second toggle, and
  nothing at all unless the client turned the summary on.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.WellnessSummarySharing
  alias MilosTrainingWeb.Schemas.Buddies, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Buddies"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:show,
    summary: "A client's weekly wellness summary (only when the client allowed it)",
    parameters: [
      %Parameter{name: :user_id, in: :path, required: true, schema: S.uuid()},
      %Parameter{
        name: :week,
        in: :query,
        required: false,
        description: "Any date of the week; the last completed week when left out",
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [ok: {"Summary", "application/json", S.client_summary_response()}]
  )

  def show(conn, %{user_id: user_id} = params) do
    with {:ok, summary} <-
           WellnessSummarySharing.client_summary(conn.assigns.tenant_context, user_id, params),
         do: json(conn, summary)
  end
end
