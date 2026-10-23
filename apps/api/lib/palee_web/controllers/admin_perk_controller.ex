defmodule PaleeWeb.AdminPerkController do
  @moduledoc """
  Staff run the business's partner perks (ADR-191): list with claim and use
  counts, create, edit (versioned terms), publish, pause, end and delete,
  the pool of unique codes, the claims export (JSON pages or CSV), and marking a claim used or
  revoking it. Capability `manage_perks`; branches follow ADR-186 §8.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Perks
  alias PaleeWeb.Schemas.Perks, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Perks"])
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
    forbidden: {"Outside your branches, or the business isn't activated", "application/json", S.error()},
    conflict: {"The perk can't take this step now", "application/json", S.error()},
    unprocessable_entity: {"Invalid perk", "application/json", %Schema{type: :object}}
  ]
  @perk_response [ok: {"Perk", "application/json", S.staff_response()}]
  @claim_response [ok: {"Claim", "application/json", S.staff_claim_response()}]

  operation(:index,
    summary: "The business's perks with claim and use counts",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: S.status()
      }
    ],
    responses: [ok: {"Perks", "application/json", S.staff_list()}]
  )

  def index(conn, params), do: json(conn, Perks.list(context(conn), params))

  operation(:show,
    summary: "One perk",
    parameters: [@id],
    responses: @perk_response ++ @refused
  )

  def show(conn, %{id: id}) do
    with {:ok, perk} <- Perks.show(context(conn), id), do: json(conn, %{perk: perk})
  end

  operation(:create,
    summary: "Create a perk (a draft); the method defaults to shared_code",
    request_body: S.body(S.perk_input([:partner_name, :benefit])),
    responses: [created: {"Perk", "application/json", S.staff_response()}] ++ @refused
  )

  def create(conn, _params) do
    with {:ok, perk} <- Perks.create(context(conn), conn.body_params) do
      conn |> put_status(:created) |> json(%{perk: perk})
    end
  end

  operation(:update,
    summary: "Edit a perk",
    description:
      "Benefit, rules, redemption and terms amend the current version until the first claim, then make a new version: members keep the terms they claimed. Once claimed, the redemption method is fixed; an ended perk is read-only.",
    parameters: [@id],
    request_body: S.body(S.perk_input()),
    responses: @perk_response ++ @refused
  )

  def update(conn, %{id: id}) do
    with {:ok, perk} <- Perks.update(context(conn), id, conn.body_params),
         do: json(conn, %{perk: perk})
  end

  operation(:versions,
    summary: "The perk's versions of its terms, newest first",
    parameters: [@id],
    responses: [ok: {"Versions", "application/json", S.versions_response()}] ++ @refused
  )

  def versions(conn, %{id: id}) do
    with {:ok, versions} <- Perks.versions(context(conn), id), do: json(conn, versions)
  end

  operation(:delete,
    summary: "Delete a perk nobody has claimed",
    parameters: [@id],
    responses: [no_content: "Deleted"] ++ @refused
  )

  def delete(conn, %{id: id}) do
    with :ok <- Perks.delete(context(conn), id), do: send_resp(conn, :no_content, "")
  end

  operation(:publish,
    summary: "Publish: clients see and claim it (a business in demo mode can't)",
    parameters: [@id],
    responses: @perk_response ++ @refused
  )

  def publish(conn, %{id: id}), do: respond_perk(conn, Perks.publish(context(conn), id))

  operation(:pause,
    summary: "Pause: no new claims; claimed codes keep working",
    parameters: [@id],
    responses: @perk_response ++ @refused
  )

  def pause(conn, %{id: id}), do: respond_perk(conn, Perks.pause(context(conn), id))

  operation(:expire,
    summary: "End now: nothing can be claimed or used any more",
    parameters: [@id],
    responses: @perk_response ++ @refused
  )

  def expire(conn, %{id: id}), do: respond_perk(conn, Perks.expire(context(conn), id))

  defp respond_perk(conn, {:ok, perk}), do: json(conn, %{perk: perk})
  defp respond_perk(_conn, error), do: error

  operation(:add_codes,
    summary: "Add the partner's single-use codes to a code_pool perk (paste or CSV; top up any time)",
    parameters: [@id],
    request_body: S.body(S.codes_input()),
    responses: [ok: {"Pool", "application/json", S.codes_response()}] ++ @refused
  )

  def add_codes(conn, %{id: id}) do
    with {:ok, result} <- Perks.add_codes(context(conn), id, conn.body_params),
         do: json(conn, result)
  end

  operation(:claims,
    summary: "The perk's claims and uses (export), oldest first, a page at a time",
    parameters: [
      @id,
      %Parameter{
        name: :after,
        in: :query,
        required: false,
        description: "The `next` cursor of the previous page.",
        schema: %Schema{type: :string, maxLength: 200}
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 1000}
      }
    ],
    responses: [ok: {"Claims", "application/json", S.claims_export()}] ++ @refused
  )

  def claims(conn, %{id: id} = params) do
    with {:ok, export} <- Perks.claims(context(conn), id, params), do: json(conn, export)
  end

  operation(:claims_csv,
    summary: "The perk's claims and uses as CSV",
    parameters: [@id],
    responses:
      [ok: {"CSV", "text/csv", %Schema{type: :string, format: :binary}}] ++ @refused
  )

  def claims_csv(conn, %{id: id}) do
    with {:ok, %{perk: perk, csv: csv}} <- Perks.claims_csv(context(conn), id) do
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="perk-#{perk.id}-claims.csv")
      )
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, csv)
    end
  end

  operation(:use_claim,
    summary: "Mark a claim used (the partner confirmed it another way)",
    parameters: [@id],
    responses: @claim_response ++ @refused
  )

  def use_claim(conn, %{id: id}) do
    with {:ok, claim} <- Perks.mark_used(context(conn), id), do: json(conn, %{claim: claim})
  end

  operation(:revoke_claim,
    summary: "Revoke an unused claim: its code or QR stops working and its place is freed",
    parameters: [@id],
    responses: @claim_response ++ @refused
  )

  def revoke_claim(conn, %{id: id}) do
    with {:ok, claim} <- Perks.revoke_claim(context(conn), id), do: json(conn, %{claim: claim})
  end

  defp context(conn), do: conn.assigns.tenant_context
end
