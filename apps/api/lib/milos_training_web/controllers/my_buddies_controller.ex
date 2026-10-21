defmodule MilosTrainingWeb.MyBuddiesController do
  @moduledoc """
  Εγώ › Buddy για στήριξη (ADR-160): your buddies and the people you
  support, invitations by id or by a link you share, accepting, declining,
  leaving (quietly), what each buddy receives, and your quiet hours and
  phone sharing.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.Buddies
  alias MilosTrainingWeb.Schemas.Buddies, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Buddies"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}
  @link {"Buddy link", "application/json", S.link_response()}

  operation(:index,
    summary: "Your buddies, the people you support, invitations waiting for you, your settings",
    responses: [ok: {"Overview", "application/json", S.overview()}]
  )

  def index(conn, _params) do
    with {:ok, overview} <- Buddies.overview(conn.assigns.user_context), do: json(conn, overview)
  end

  operation(:candidates,
    summary:
      "People you can invite: your coaches and follows; with q, people of a club in common",
    parameters: [
      %Parameter{name: :q, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Candidates", "application/json", S.candidates_response()}]
  )

  def candidates(conn, params) do
    with {:ok, candidates} <- Buddies.candidates(conn.assigns.user_context, params),
         do: json(conn, %{candidates: candidates})
  end

  operation(:invite,
    summary: "Invite someone you know here (they must accept; expires after 7 days)",
    request_body: S.body(S.invite_request()),
    responses: [created: @link]
  )

  def invite(conn, _params) do
    with {:ok, link} <- Buddies.invite(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{link: link})
    end
  end

  operation(:create_invite_link,
    summary: "An invite link for someone not on Milos yet (shown once; expires after 7 days)",
    responses: [created: {"Invite link", "application/json", S.invite_link_response()}]
  )

  def create_invite_link(conn, _params) do
    with {:ok, invite} <- Buddies.create_invite_link(conn.assigns.user_context) do
      conn |> put_status(:created) |> json(invite)
    end
  end

  operation(:claim,
    summary: "Claim an invite link: you become that person's buddy",
    parameters: [
      %Parameter{name: :token, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [ok: @link]
  )

  def claim(conn, %{token: token}) do
    with {:ok, link} <- Buddies.claim_invite(conn.assigns.user_context, token),
         do: json(conn, %{link: link})
  end

  operation(:accept,
    summary: "Accept an invitation to support someone",
    parameters: [@id],
    responses: [ok: @link]
  )

  def accept(conn, %{id: id}) do
    with {:ok, link} <- Buddies.accept(conn.assigns.user_context, id),
         do: json(conn, %{link: link})
  end

  operation(:decline,
    summary: "Decline an invitation (the other person is not notified)",
    parameters: [@id],
    responses: [ok: @link]
  )

  def decline(conn, %{id: id}) do
    with {:ok, link} <- Buddies.decline(conn.assigns.user_context, id),
         do: json(conn, %{link: link})
  end

  operation(:leave,
    summary: "Stop, from either side, at any time (no push; the other sees it on their page)",
    parameters: [@id],
    responses: [ok: @link]
  )

  def leave(conn, %{id: id}) do
    with {:ok, link} <- Buddies.leave(conn.assigns.user_context, id),
         do: json(conn, %{link: link})
  end

  operation(:update,
    summary: "What your buddy receives: only what you send, or also the weekly counts summary",
    parameters: [@id],
    request_body: S.body(S.update_request()),
    responses: [ok: @link]
  )

  def update(conn, %{id: id}) do
    with {:ok, link} <- Buddies.update_link(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, %{link: link})
  end

  operation(:settings,
    summary: "Your quiet hours and whether buddies may see your phone",
    responses: [ok: {"Settings", "application/json", S.settings_response()}]
  )

  def settings(conn, _params) do
    with {:ok, settings} <- Buddies.settings(conn.assigns.user_context),
         do: json(conn, %{settings: settings})
  end

  operation(:update_settings,
    summary: "Change your quiet hours, zone or phone sharing (off by default)",
    request_body: S.body(S.settings_request()),
    responses: [ok: {"Settings", "application/json", S.settings_response()}]
  )

  def update_settings(conn, _params) do
    with {:ok, settings} <-
           Buddies.update_settings(conn.assigns.user_context, conn.body_params),
         do: json(conn, %{settings: settings})
  end
end
