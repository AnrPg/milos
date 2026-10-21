defmodule PaleeWeb.OpenClubController do
  @moduledoc "«Βρες», open clubs, a club's «Μέλη» and reports, from your personal session (ADR-143)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{ClubMembers, CommunityReports, OpenClubs}
  alias PaleeWeb.Schemas.Community, as: C
  alias PaleeWeb.Schemas.CommunityGroups, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @q %Parameter{
    name: :q,
    in: :query,
    required: false,
    schema: %Schema{type: :string, maxLength: 80}
  }
  @club {"Club", "application/json", S.open_club_response()}

  operation(:discover,
    summary: "«Βρες»: open clubs to join and your gyms' groups you are not in",
    parameters: [@q],
    responses: [ok: {"Found", "application/json", S.discover_response()}]
  )

  def discover(conn, params) do
    with {:ok, found} <- OpenClubs.discover(conn.assigns.user_context, params),
         do: json(conn, found)
  end

  operation(:show,
    summary: "An open club: what it is, how many are in it and where you stand",
    parameters: [@id],
    responses: [ok: @club]
  )

  def show(conn, %{id: id}), do: reply(conn, OpenClubs.show(conn.assigns.user_context, id))

  operation(:join,
    summary: "Join an open club (or ask, when it asks for approval)",
    parameters: [@id],
    responses: [ok: @club]
  )

  def join(conn, %{id: id}), do: reply(conn, OpenClubs.join(conn.assigns.user_context, id))

  operation(:leave,
    summary: "Leave an open club",
    parameters: [@id],
    responses: [ok: @club]
  )

  def leave(conn, %{id: id}), do: reply(conn, OpenClubs.leave(conn.assigns.user_context, id))

  operation(:set_notify_level,
    summary: "How much you hear from an open club",
    parameters: [@id],
    request_body: C.body(C.notify_request()),
    responses: [ok: {"Level", "application/json", C.notify_response()}]
  )

  def set_notify_level(conn, %{id: id}) do
    with {:ok, level} <-
           OpenClubs.set_notify_level(
             conn.assigns.user_context,
             id,
             conn.body_params.notify_level
           ),
         do: json(conn, %{club_id: id, notify_level: level})
  end

  operation(:members,
    summary: "A club's members (not you), coaches first",
    parameters: [@id, @q],
    responses: [ok: {"Members", "application/json", S.members_response()}]
  )

  def members(conn, %{id: id} = params) do
    with {:ok, result} <- ClubMembers.list(conn.assigns.user_context, id, params),
         do: json(conn, result)
  end

  operation(:report,
    summary: "Report a post, a comment or a group; it disappears for you and staff look at it",
    request_body: S.body(S.report_request()),
    responses: [created: {"Reported", "application/json", S.report_response()}]
  )

  def report(conn, _params) do
    with {:ok, result} <- CommunityReports.report(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  defp reply(conn, {:ok, club}), do: json(conn, %{club: club})
  defp reply(_conn, error), do: error
end
