defmodule MilosTrainingWeb.AdminReferralController do
  @moduledoc """
  Staff run the box's invites (ADR-156, board 11 Q4, Q6, Q7): the list with
  each friend's stage, approving or rejecting the referral an invite opened,
  «Δόθηκε» for rewards handed over by hand, giving an invite to another
  member and applying the friend's gift.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.Referrals
  alias MilosTrainingWeb.Schemas.Referrals, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Referrals"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such invite", "application/json", %Schema{type: :object}},
    unprocessable_entity:
      {"The invite can't take this step", "application/json", %Schema{type: :object}}
  ]
  @invite_response [ok: {"Invite", "application/json", S.staff_invite_response()}]

  operation(:index,
    summary: "The box's invites, newest first; filter review keeps those waiting for approval",
    parameters: [
      %Parameter{
        name: :filter,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["review"]}
      }
    ],
    responses: [ok: {"Invites", "application/json", S.staff_list()}]
  )

  def index(conn, params),
    do: json(conn, Referrals.staff_list(context(conn), Map.get(params, :filter)))

  operation(:approve,
    summary: "Approve the referral: its reward is created, and a credit lands at once",
    parameters: [@id],
    responses: @invite_response ++ @refused
  )

  def approve(conn, %{id: id}) do
    with {:ok, invite} <- Referrals.approve(context(conn), id, actor(conn)),
         do: json(conn, %{invite: invite})
  end

  operation(:reject,
    summary: "Reject the referral; no reward is made",
    parameters: [@id],
    request_body: S.body(S.note_request()),
    responses: @invite_response ++ @refused
  )

  def reject(conn, %{id: id}) do
    with {:ok, invite} <-
           Referrals.reject(context(conn), id, actor(conn), Map.get(conn.body_params, :note)),
         do: json(conn, %{invite: invite})
  end

  operation(:given,
    summary: "«Δόθηκε»: an approved reward that isn't a credit was handed over",
    parameters: [@id],
    responses: @invite_response ++ @refused
  )

  def given(conn, %{id: id}) do
    with {:ok, invite} <- Referrals.mark_given(context(conn), id, actor(conn)),
         do: json(conn, %{invite: invite})
  end

  operation(:reassign,
    summary: "Give an invite that hasn't qualified yet to another member, with a note",
    parameters: [@id],
    request_body: S.body(S.reassign_request()),
    responses: @invite_response ++ @refused
  )

  def reassign(conn, %{id: id}) do
    with {:ok, invite} <- Referrals.reassign(context(conn), id, conn.body_params, actor(conn)),
         do: json(conn, %{invite: invite})
  end

  operation(:friend_gift,
    summary:
      "Apply the friend's gift on their first sale (free days, a credit or a described gift)",
    parameters: [@id],
    responses: @invite_response ++ @refused
  )

  def friend_gift(conn, %{id: id}) do
    with {:ok, invite} <- Referrals.apply_friend_gift(context(conn), id, actor(conn)),
         do: json(conn, %{invite: invite})
  end

  defp context(conn), do: conn.assigns.tenant_context
  defp actor(conn), do: conn.assigns.tenant_context.user_id
end
