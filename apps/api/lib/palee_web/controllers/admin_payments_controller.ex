defmodule PaleeWeb.AdminPaymentsController do
  @moduledoc """
  Staff › Finance › online payments (ADR-246/247): the business's own
  provider account (credentials are written, never read back), payments,
  refunds and asking the provider again.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Payments.OnlinePayments
  alias PaleeWeb.Schemas.Payments, as: P

  action_fallback PaleeWeb.FallbackController

  tags(["Payments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:account,
    summary: "The business's payment provider account (never its credentials)",
    responses: [ok: {"Account", "application/json", P.account_status()}]
  )

  def account(conn, _params), do: json(conn, OnlinePayments.account(conn.assigns.tenant_context))

  operation(:save_account,
    summary: "Connect the business's own Viva or Stripe account",
    description:
      "The provider checks the credentials before they are saved. Secrets left out keep " <>
        "their saved values when the provider stays the same.",
    request_body: P.body(P.account_body()),
    responses: [ok: {"Account", "application/json", P.account_status()}]
  )

  def save_account(conn, _params) do
    with {:ok, status} <-
           OnlinePayments.save_account(conn.assigns.tenant_context, conn.body_params) do
      json(conn, status)
    end
  end

  operation(:index,
    summary: "Online payments, newest first",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ~w(scheduled awaiting_payer processing succeeded failed cancelled expired)
        }
      },
      %Parameter{name: :user_id, in: :query, required: false, schema: P.uuid()},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Payments", "application/json", P.intent_page()}]
  )

  def index(conn, params) do
    filters = Map.take(params, [:status, :user_id, :limit, :offset])
    json(conn, OnlinePayments.list(conn.assigns.tenant_context, filters))
  end

  operation(:show,
    summary: "One online payment with its refunds",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent_detail())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.get(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:refund,
    summary: "Give back part or all of a payment through the provider",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    request_body: P.body(P.refund_body()),
    responses: [ok: {"Refund", "application/json", P.one(:refund, P.refund())}]
  )

  def refund(conn, %{id: id}) do
    with {:ok, refund} <-
           OnlinePayments.refund(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{refund: refund})
    end
  end

  operation(:retry,
    summary: "Ask the provider about a payment now",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def retry(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.retry(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:save_options,
    summary: "Choose what members pay online and who hears about failed charges",
    description: "Keys left out keep their value. Every purpose is on by default.",
    request_body: P.body(P.options_body()),
    responses: [ok: {"Account", "application/json", P.account_status()}]
  )

  def save_options(conn, _params) do
    with {:ok, status} <-
           OnlinePayments.save_options(conn.assigns.tenant_context, conn.body_params) do
      json(conn, status)
    end
  end

  operation(:attention,
    summary: "Saved-card charges that need a person (Εκκρεμότητες)",
    description:
      "Declined and waiting for a retry, or failed for good, until staff close them or " <>
        "the purpose is paid. Each names the member (`member_name`).",
    responses: [ok: {"Payments", "application/json", P.attention_page()}]
  )

  def attention(conn, _params),
    do: json(conn, OnlinePayments.attention(conn.assigns.tenant_context))

  operation(:retry_charge,
    summary: "Charge the saved card once more now",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def retry_charge(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.retry_charge(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:dismiss_charge,
    summary: "Close a failed charge (e.g. paid at the desk); stops its retries",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def dismiss_charge(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.dismiss_charge(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:card_link,
    summary: "Send the member the link to pay with another card again",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def card_link(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.send_card_link(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:connect,
    summary: "Start connecting the business's Stripe or Viva account with one button",
    description:
      "Answers the provider page to send the owner to. There they sign in or open a " <>
        "merchant account and allow Palee; the provider sends them back to " <>
        "`/api/payments/connect/callback`, which opens the settings page with `connect=ok` " <>
        "or `connect=<error code>`.",
    request_body: P.body(P.connect_body()),
    responses: [ok: {"Provider page", "application/json", P.connect_start()}]
  )

  def connect(conn, _params) do
    with {:ok, start} <-
           OnlinePayments.connect_start(conn.assigns.tenant_context, conn.body_params) do
      json(conn, start)
    end
  end

  operation(:disconnect,
    summary: "Stop online payments: saved cards are no longer charged",
    description: "A one-button connection also loses Palee's access at the provider.",
    responses: [ok: {"Account", "application/json", P.account_status()}]
  )

  def disconnect(conn, _params) do
    with {:ok, status} <- OnlinePayments.disconnect(conn.assigns.tenant_context) do
      json(conn, status)
    end
  end
end
