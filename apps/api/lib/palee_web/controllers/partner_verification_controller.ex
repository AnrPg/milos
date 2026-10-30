defmodule PaleeWeb.PartnerVerificationController do
  @moduledoc """
  Partners verification (ADR-280 §5): the person's state and sponsor path
  (`/me/partners/verification*`) and the sponsor's side
  (`/me/partners/vouch-requests*`, `/me/partners/vouch-links/*`,
  `/me/partners/vouching`).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.{PartnerSponsoring, PartnerVerification}
  alias PaleeWeb.Schemas.PartnerVerification, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Partners verification"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: S.uuid()}

  defp ctx(conn), do: conn.assigns.user_context

  # ------------------------------------------------------------ the person

  operation(:show,
    summary: "Your Partners verification: state, next step, your request",
    description:
      "A person with an active membership of a live box or coach is verified here on first use.",
    responses: [ok: {"Verification", "application/json", S.overview()}]
  )

  def show(conn, _params) do
    with {:ok, overview} <- PartnerVerification.overview(ctx(conn)), do: json(conn, overview)
  end

  operation(:consent,
    summary: "Agree to the Palee check and open your request (sponsor path)",
    responses: [ok: {"Verification", "application/json", S.overview()}]
  )

  def consent(conn, _params) do
    with {:ok, overview} <- PartnerVerification.consent(ctx(conn)), do: json(conn, overview)
  end

  operation(:sponsor_candidates,
    summary: "Your Buddies as possible sponsors, each marked whether they may vouch",
    responses: [ok: {"Candidates", "application/json", S.sponsor_candidates()}]
  )

  def sponsor_candidates(conn, _params) do
    with {:ok, result} <- PartnerVerification.sponsor_candidates(ctx(conn)),
         do: json(conn, result)
  end

  operation(:request_sponsor,
    summary: "Ask a Buddy to vouch for you",
    request_body: S.body(S.sponsor_request()),
    responses: [ok: {"Sponsorship", "application/json", S.sponsorship_response()}]
  )

  def request_sponsor(conn, _params) do
    with {:ok, result} <- PartnerVerification.request_sponsor(ctx(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:cancel_sponsor,
    summary: "Withdraw an unanswered request to a sponsor (the sponsor's person id)",
    parameters: [@id],
    responses: [ok: {"Sponsorship", "application/json", S.sponsorship_response()}]
  )

  def cancel_sponsor(conn, %{id: sponsor_id}) do
    with {:ok, result} <- PartnerVerification.cancel_sponsor(ctx(conn), sponsor_id),
         do: json(conn, result)
  end

  operation(:create_link,
    summary: "A single-use, 10-minute link (and QR) for a sponsor outside your Buddies",
    responses: [created: {"Link", "application/json", S.link()}]
  )

  def create_link(conn, _params) do
    with {:ok, link} <- PartnerVerification.create_link(ctx(conn)),
         do: conn |> put_status(:created) |> json(link)
  end

  operation(:send_phone_code,
    summary: "Send a 6-digit code to your mobile number",
    request_body: S.body(S.phone_request()),
    responses: [ok: {"Sent", "application/json", S.phone_sent()}]
  )

  def send_phone_code(conn, _params) do
    with {:ok, sent} <- PartnerVerification.send_phone_code(ctx(conn), conn.body_params),
         do: json(conn, sent)
  end

  operation(:confirm_phone,
    summary: "Confirm your number with the code it received",
    request_body: S.body(S.code_request()),
    responses: [ok: {"Verification", "application/json", S.overview()}]
  )

  def confirm_phone(conn, _params) do
    with {:ok, overview} <- PartnerVerification.confirm_phone(ctx(conn), conn.body_params),
         do: json(conn, overview)
  end

  operation(:selfie_upload_url,
    summary: "A presigned upload for the selfie holding your code",
    request_body: S.body(S.selfie_upload_request()),
    responses: [ok: {"Upload", "application/json", S.selfie_upload()}]
  )

  def selfie_upload_url(conn, _params) do
    with {:ok, upload} <- PartnerVerification.selfie_upload_url(ctx(conn), conn.body_params),
         do: json(conn, upload)
  end

  operation(:submit,
    summary: "Send your request with the uploaded selfie to the Palee team",
    request_body: S.body(S.submit_request()),
    responses: [ok: {"Verification", "application/json", S.overview()}]
  )

  def submit(conn, _params) do
    with {:ok, overview} <- PartnerVerification.submit(ctx(conn), conn.body_params),
         do: json(conn, overview)
  end

  operation(:withdraw,
    summary: "Withdraw your request: phone, selfie, open sponsor requests and links are deleted",
    responses: [ok: {"Verification", "application/json", S.overview()}]
  )

  def withdraw(conn, _params) do
    with {:ok, overview} <- PartnerVerification.withdraw(ctx(conn)), do: json(conn, overview)
  end

  # ------------------------------------------------------------ the sponsor

  operation(:vouch_requests,
    summary: "People who asked you to vouch for them, and your quota",
    responses: [ok: {"Requests", "application/json", S.vouch_requests()}]
  )

  def vouch_requests(conn, _params) do
    with {:ok, result} <- PartnerSponsoring.vouch_requests(ctx(conn)), do: json(conn, result)
  end

  operation(:decide_vouch,
    summary: "Vouch for or decline someone who asked you",
    parameters: [@id],
    request_body: S.body(S.vouch_decision_request()),
    responses: [ok: {"Answer", "application/json", S.vouch_result()}]
  )

  def decide_vouch(conn, %{id: id}) do
    with {:ok, result} <- PartnerSponsoring.decide(ctx(conn), id, conn.body_params),
         do: json(conn, result)
  end

  operation(:inspect_link,
    summary: "Who a sponsor link is for, and whether you may vouch",
    request_body: S.body(S.token_request()),
    responses: [ok: {"Link", "application/json", S.link_inspection()}]
  )

  def inspect_link(conn, _params) do
    with {:ok, result} <- PartnerSponsoring.inspect_link(ctx(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:vouch_by_link,
    summary: "Vouch through a sponsor link (single use)",
    request_body: S.body(S.token_request()),
    responses: [ok: {"Vouched", "application/json", S.vouch_result()}]
  )

  def vouch_by_link(conn, _params) do
    with {:ok, result} <- PartnerSponsoring.vouch_by_link(ctx(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:vouching,
    summary: "Your own standing as a sponsor: quota left, any pause",
    responses: [ok: {"Vouching", "application/json", S.vouching()}]
  )

  def vouching(conn, _params) do
    with {:ok, result} <- PartnerSponsoring.vouching(ctx(conn)), do: json(conn, result)
  end
end
