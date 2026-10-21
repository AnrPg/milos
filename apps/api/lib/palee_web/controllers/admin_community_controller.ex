defmodule PaleeWeb.AdminCommunityController do
  @moduledoc "«Κοινότητα» for staff (ADR-143, board 7 Q3, Q5, Q6): groups, reports and open clubs."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{CommunityGroups, CommunityReports, OpenClubs}
  alias PaleeWeb.Schemas.CommunityGroups, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: @uuid}
  @club {"Club", "application/json", S.open_club_response()}
  @staff_group {"Group", "application/json", S.staff_group_response()}

  operation(:groups,
    summary: "Proposed, live and archived groups, and the gym's group rule",
    responses: [ok: {"Groups", "application/json", S.staff_groups_response()}]
  )

  def groups(conn, _params) do
    with {:ok, result} <- CommunityGroups.staff_overview(conn.assigns.tenant_context),
         do: json(conn, result)
  end

  operation(:decide_group,
    summary: "Approve or decline a proposed group",
    parameters: [@id],
    request_body: S.body(S.decision_request()),
    responses: [ok: @staff_group]
  )

  def decide_group(conn, %{id: id}) do
    with {:ok, group} <-
           CommunityGroups.decide(conn.assigns.tenant_context, id, conn.body_params.decision),
         do: json(conn, %{group: group})
  end

  operation(:reopen_group,
    summary: "Bring an archived group back",
    parameters: [@id],
    responses: [ok: @staff_group]
  )

  def reopen_group(conn, %{id: id}) do
    with {:ok, group} <- CommunityGroups.reopen(conn.assigns.tenant_context, id),
         do: json(conn, %{group: group})
  end

  operation(:update_settings,
    summary: "Whether members may start groups, and whether staff approve them first",
    request_body: S.body(S.settings_request()),
    responses: [ok: {"Settings", "application/json", S.settings_response()}]
  )

  def update_settings(conn, _params) do
    with {:ok, settings} <-
           CommunityGroups.put_settings(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, settings)
  end

  operation(:reports,
    summary: "Open reports, one row per reported item",
    responses: [ok: {"Reports", "application/json", S.reports_response()}]
  )

  def reports(conn, _params) do
    with {:ok, reports} <- CommunityReports.queue(conn.assigns.tenant_context),
         do: json(conn, %{reports: reports})
  end

  operation(:act_on_report,
    summary: "Act on a reported item; every open report on it closes",
    request_body: S.body(S.report_action_request()),
    responses: [ok: {"Done", "application/json", S.report_action_response()}]
  )

  def act_on_report(conn, _params) do
    %{target_type: type, target_id: id, action: action} = conn.body_params

    with {:ok, result} <- CommunityReports.act(conn.assigns.tenant_context, type, id, action),
         do: json(conn, result)
  end

  operation(:clubs,
    summary: "The gym's open clubs",
    responses: [ok: {"Clubs", "application/json", S.open_clubs_response()}]
  )

  def clubs(conn, _params) do
    with {:ok, clubs} <- OpenClubs.staff_list(conn.assigns.tenant_context),
         do: json(conn, %{clubs: clubs})
  end

  operation(:create_club,
    summary: "Start an open club",
    request_body: S.body(S.open_club_request()),
    responses: [created: @club]
  )

  def create_club(conn, _params) do
    with {:ok, club} <- OpenClubs.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{club: club})
    end
  end

  operation(:club,
    summary: "An open club with its members and requests",
    parameters: [@id],
    responses: [ok: @club]
  )

  def club(conn, %{id: id}),
    do: reply(conn, OpenClubs.staff_show(conn.assigns.tenant_context, id))

  operation(:update_club,
    summary: "Edit an open club",
    parameters: [@id],
    request_body: S.body(S.open_club_request([])),
    responses: [ok: @club]
  )

  def update_club(conn, %{id: id}),
    do: reply(conn, OpenClubs.update(conn.assigns.tenant_context, id, conn.body_params))

  operation(:archive_club,
    summary: "Archive an open club",
    parameters: [@id],
    responses: [ok: {"Archived", "application/json", S.archived_response()}]
  )

  def archive_club(conn, %{id: id}) do
    with {:ok, result} <- OpenClubs.archive(conn.assigns.tenant_context, id),
         do: json(conn, result)
  end

  operation(:answer_club_request,
    summary: "Let someone into an open club, or turn them down",
    parameters: [@id, @user_id],
    request_body: S.body(S.approve_request()),
    responses: [ok: @club]
  )

  def answer_club_request(conn, %{id: id, user_id: user_id}) do
    reply(
      conn,
      OpenClubs.answer_request(conn.assigns.tenant_context, id, user_id, conn.body_params.approve)
    )
  end

  operation(:remove_club_member,
    summary: "Remove someone from an open club",
    parameters: [@id, @user_id],
    responses: [ok: @club]
  )

  def remove_club_member(conn, %{id: id, user_id: user_id}),
    do: reply(conn, OpenClubs.remove_member(conn.assigns.tenant_context, id, user_id))

  defp reply(conn, {:ok, club}), do: json(conn, %{club: club})
  defp reply(_conn, error), do: error
end
