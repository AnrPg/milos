defmodule MilosTrainingWeb.CommunityController do
  @moduledoc "Clubs and channels (ADR-138): the member's clubs and their choices about them."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{CommunityPreferences, GetWodTodayCard, ListMyClubs}
  alias MilosTrainingWeb.Schemas.Community, as: S
  alias OpenApiSpex.Parameter

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  operation(:my_clubs,
    summary: "Your clubs across every gym you belong to, with their channels",
    responses: [ok: {"Clubs", "application/json", S.clubs_response()}]
  )

  def my_clubs(conn, _params) do
    with {:ok, clubs} <- ListMyClubs.call(conn.assigns.user_context) do
      json(conn, %{clubs: clubs})
    end
  end

  operation(:set_notify_level,
    summary: "How much you hear from a club",
    parameters: [@id],
    request_body: S.body(S.notify_request()),
    responses: [ok: {"Level", "application/json", S.notify_response()}]
  )

  def set_notify_level(conn, %{id: id}) do
    with {:ok, level} <-
           CommunityPreferences.set_notify_level(
             conn.assigns.tenant_context,
             id,
             conn.body_params.notify_level
           ) do
      json(conn, %{club_id: id, notify_level: level})
    end
  end

  operation(:join_channel,
    summary: "Join an opt-in channel",
    parameters: [@id],
    responses: [ok: {"Membership", "application/json", S.channel_membership_response()}]
  )

  def join_channel(conn, %{id: id}) do
    with {:ok, result} <- CommunityPreferences.join_channel(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:leave_channel,
    summary: "Leave an opt-in channel",
    parameters: [@id],
    responses: [ok: {"Membership", "application/json", S.channel_membership_response()}]
  )

  def leave_channel(conn, %{id: id}) do
    with {:ok, result} <- CommunityPreferences.leave_channel(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:wod_today,
    summary: "The gym's #wod card for a day: its WOD, classes and leaderboard",
    parameters: [
      %Parameter{
        name: :date,
        in: :query,
        required: false,
        schema: %OpenApiSpex.Schema{type: :string, format: :date},
        description: "Local date; today in `timezone` when omitted"
      },
      %Parameter{
        name: :timezone,
        in: :query,
        required: false,
        schema: %OpenApiSpex.Schema{type: :string},
        description: "IANA time zone of the member, e.g. Europe/Athens"
      }
    ],
    responses: [ok: {"Card", "application/json", S.wod_today_response()}]
  )

  def wod_today(conn, params) do
    with {:ok, card} <- GetWodTodayCard.call(conn.assigns.tenant_context, params) do
      json(conn, card)
    end
  end
end
