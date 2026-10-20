defmodule MilosTrainingWeb.CommunityGroupController do
  @moduledoc "Member groups in your gym's club (ADR-143, board 7 Q2)."

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.CommunityGroups
  alias MilosTrainingWeb.Schemas.CommunityGroups, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Community"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: @uuid}
  @group {"Group", "application/json", S.group_response()}

  operation(:index,
    summary: "The club's live groups and whether you can start one",
    responses: [ok: {"Groups", "application/json", S.groups_response()}]
  )

  def index(conn, _params) do
    with {:ok, result} <- CommunityGroups.list(conn.assigns.tenant_context),
         do: json(conn, result)
  end

  operation(:create,
    summary: "Start a group (it waits for staff when the gym asks for approval)",
    request_body: S.body(S.group_request()),
    responses: [created: @group]
  )

  def create(conn, _params) do
    with {:ok, group} <- CommunityGroups.propose(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{group: group})
    end
  end

  operation(:show,
    summary: "A group with its members (and requests, for its admins)",
    parameters: [@id],
    responses: [ok: @group]
  )

  def show(conn, %{id: id}),
    do: reply(conn, CommunityGroups.show(conn.assigns.tenant_context, id))

  operation(:update,
    summary: "Admins: rename a group, describe it, or change how people join",
    parameters: [@id],
    request_body: S.body(S.group_update_request()),
    responses: [ok: @group]
  )

  def update(conn, %{id: id}),
    do: reply(conn, CommunityGroups.update(conn.assigns.tenant_context, id, conn.body_params))

  operation(:join,
    summary: "Join a group, or ask to when its admins let people in",
    parameters: [@id],
    responses: [ok: @group]
  )

  def join(conn, %{id: id}),
    do: reply(conn, CommunityGroups.join(conn.assigns.tenant_context, id))

  operation(:leave,
    summary: "Leave a group (the last admin hands over first; the last member archives it)",
    parameters: [@id],
    responses: [ok: {"Outcome", "application/json", S.group_outcome_response()}]
  )

  def leave(conn, %{id: id}) do
    with {:ok, outcome} <- CommunityGroups.leave(conn.assigns.tenant_context, id),
         do: json(conn, outcome)
  end

  operation(:answer_request,
    summary: "Admins: let someone in, or turn the request down",
    parameters: [@id, @user_id],
    request_body: S.body(S.approve_request()),
    responses: [ok: @group]
  )

  def answer_request(conn, %{id: id, user_id: user_id}) do
    reply(
      conn,
      CommunityGroups.answer_request(
        conn.assigns.tenant_context,
        id,
        user_id,
        conn.body_params.approve
      )
    )
  end

  operation(:set_admin,
    summary: "Admins: make a member an admin, or not",
    parameters: [@id, @user_id],
    request_body: S.body(S.admin_request()),
    responses: [ok: @group]
  )

  def set_admin(conn, %{id: id, user_id: user_id}) do
    reply(
      conn,
      CommunityGroups.set_admin(conn.assigns.tenant_context, id, user_id, conn.body_params.admin)
    )
  end

  operation(:remove_member,
    summary: "Admins: remove someone from the group",
    parameters: [@id, @user_id],
    responses: [ok: @group]
  )

  def remove_member(conn, %{id: id, user_id: user_id}),
    do: reply(conn, CommunityGroups.remove_member(conn.assigns.tenant_context, id, user_id))

  operation(:archive,
    summary: "Admins: archive the group",
    parameters: [@id],
    responses: [ok: {"Outcome", "application/json", S.group_outcome_response()}]
  )

  def archive(conn, %{id: id}) do
    with {:ok, outcome} <- CommunityGroups.archive(conn.assigns.tenant_context, id),
         do: json(conn, outcome)
  end

  operation(:reopen,
    summary: "Bring back an archived group you started",
    parameters: [@id],
    responses: [ok: @group]
  )

  def reopen(conn, %{id: id}),
    do: reply(conn, CommunityGroups.reopen_mine(conn.assigns.tenant_context, id))

  defp reply(conn, {:ok, group}), do: json(conn, %{group: group})
  defp reply(_conn, error), do: error
end
