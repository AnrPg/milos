defmodule PaleeWeb.CoachPracticeController do
  @moduledoc "ADR-170: an account opens its practice as an independent coach."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.StartCoachPractice
  alias PaleeWeb.Schemas.PlatformPlans, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Coach practice"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:create,
    summary: "Open your practice as an independent coach (one per account)",
    request_body: S.coach_practice_body(),
    responses: [created: {"Practice", "application/json", S.coach_practice()}]
  )

  def create(conn, _params) do
    account = GuardianPlug.current_resource(conn)

    with {:ok, organization} <- StartCoachPractice.call(account, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(Map.take(organization, [:id, :slug, :name, :provider_kind]))
    end
  end
end
