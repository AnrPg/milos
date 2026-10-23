defmodule PaleeWeb.MyPerkController do
  @moduledoc """
  A member's partner perks (ADR-191) at every gym or coach they are a
  client of: the list, claiming one (reveals its code or QR), their claims
  and a fresh verification link for a QR.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.MemberPerks
  alias PaleeWeb.Schemas.Perks, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Me"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }
  @refused [
    not_found: {"No such perk or claim", "application/json", S.error()},
    conflict: {"Sold out, your limit reached, or no longer available", "application/json", S.error()},
    unprocessable_entity: {"Not possible", "application/json", S.error()}
  ]

  operation(:index,
    summary: "Perks you can use at every gym or coach you are a client of",
    responses: [ok: {"Perks", "application/json", S.member_list()}]
  )

  def index(conn, _params) do
    with {:ok, perks} <- MemberPerks.list(conn.assigns.user_context), do: json(conn, perks)
  end

  operation(:claims,
    summary: "Your claimed perks, newest first",
    responses: [ok: {"Claims", "application/json", S.member_claims()}]
  )

  def claims(conn, _params) do
    with {:ok, claims} <- MemberPerks.claims(conn.assigns.user_context), do: json(conn, claims)
  end

  operation(:claim,
    summary: "Claim a perk: its code or QR is revealed and the claim recorded",
    description: "Claiming again while your claim is unused returns that claim.",
    parameters: [@id],
    responses: [ok: {"Claim", "application/json", S.claim_response()}] ++ @refused
  )

  def claim(conn, %{id: id}) do
    with {:ok, result} <- MemberPerks.claim(conn.assigns.user_context, id), do: json(conn, result)
  end

  operation(:verification_link,
    summary: "A new short-lived verification link for the QR of an unused claim",
    description: "The previous link stops working.",
    parameters: [@id],
    responses: [ok: {"Claim", "application/json", S.claim_response()}] ++ @refused
  )

  def verification_link(conn, %{id: id}) do
    with {:ok, result} <- MemberPerks.verification_link(conn.assigns.user_context, id),
         do: json(conn, result)
  end
end
