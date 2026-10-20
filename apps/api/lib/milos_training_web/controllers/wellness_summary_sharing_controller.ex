defmodule MilosTrainingWeb.WellnessSummarySharingController do
  @moduledoc """
  Κοινοποίηση & ορατότητα (ADR-160): «Ευεξία · εβδομαδιαία σύνοψη» and
  «Λιγούρες στη σύνοψη», the member's grants of a weekly wellness summary
  to their coaches. Off by default; turning the summary off withdraws both.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.WellnessSummarySharing
  alias MilosTrainingWeb.Schemas.Buddies, as: S

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Buddies"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @response {"Sharing", "application/json", S.summary_sharing_response()}

  operation(:show,
    summary: "Whether your coaches get a weekly wellness summary, and cravings in it",
    responses: [ok: @response]
  )

  def show(conn, _params) do
    with {:ok, sharing} <- WellnessSummarySharing.show(conn.assigns.user_context),
         do: json(conn, %{sharing: sharing})
  end

  operation(:update,
    summary: "Turn the coach's weekly wellness summary, or cravings in it, on or off",
    request_body: S.body(S.summary_sharing_request()),
    responses: [ok: @response]
  )

  def update(conn, _params) do
    with {:ok, sharing} <-
           WellnessSummarySharing.update(conn.assigns.user_context, conn.body_params),
         do: json(conn, %{sharing: sharing})
  end
end
