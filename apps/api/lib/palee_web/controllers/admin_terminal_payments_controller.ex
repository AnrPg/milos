defmodule PaleeWeb.AdminTerminalPaymentsController do
  @moduledoc """
  Staff › desk › Tap to Pay (ADR-249): open a card payment for the
  provider's terminal app on the staff phone, post back what the app
  returned (confirmed with the provider before anything is recorded),
  follow it and give up on it. ADR-264: a walk-in may pay a free sale; a
  tip and a card surcharge the provider confirmed are shown apart.
  ADR-272: availability says why not, the payment carries its receipt and
  whose tip it is, and the receipt can be emailed from the result screen.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.Payments.TerminalPayments
  alias PaleeWeb.Schemas.FiscalTax, as: FT
  alias PaleeWeb.Schemas.Payments, as: P
  alias PaleeWeb.Schemas.TerminalPayments, as: T

  action_fallback PaleeWeb.FallbackController

  tags(["Payments"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:availability,
    summary: "Whether the business can take Tap to Pay now",
    responses: [ok: {"Availability", "application/json", T.availability()}]
  )

  def availability(conn, _params),
    do: json(conn, TerminalPayments.availability(conn.assigns.tenant_context))

  operation(:create,
    summary: "Open a Tap to Pay payment at the desk",
    description:
      "Answers the payment and the request the phone hands to the provider's terminal app. " <>
        "A retry with the same idempotency key answers the first payment.",
    request_body: P.body(T.start_body()),
    responses: [
      created: {"Payment", "application/json", P.one(:payment, T.terminal_payment())}
    ]
  )

  def create(conn, _params) do
    with {:ok, payment} <-
           TerminalPayments.start(conn.assigns.tenant_context, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{payment: payment})
    end
  end

  operation(:result,
    summary: "What the terminal app returned (confirmed with the provider)",
    description:
      "The phone posts the callback it received. Money is recorded only after the provider " <>
        "confirms the transaction; a duplicate callback answers the payment as it stands.",
    request_body: P.body(T.result_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, T.terminal_payment())}]
  )

  def result(conn, _params) do
    with {:ok, payment} <-
           TerminalPayments.record_result(conn.assigns.tenant_context, conn.body_params) do
      json(conn, %{payment: payment})
    end
  end

  operation(:show,
    summary: "One Tap to Pay payment",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, T.terminal_payment())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, payment} <- TerminalPayments.get(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:cancel,
    summary: "Give up on a Tap to Pay payment that has no card transaction",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    responses: [ok: {"Payment", "application/json", P.one(:payment, T.terminal_payment())}]
  )

  def cancel(conn, %{id: id}) do
    with {:ok, payment} <- TerminalPayments.cancel(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:receipt_email,
    summary: "Email the receipt of a Tap to Pay payment (ADR-272)",
    description:
      "«Αποστολή με email» on the result screen, through the document email of ADR-265. " <>
        "A walk-in's needs `to`; a member's goes to their account email when `to` is left out.",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    request_body: P.body(T.receipt_email_body()),
    responses: [
      accepted: {"Queued", "application/json", FT.document_email()},
      ok: {"The email of an earlier identical request", "application/json", FT.document_email()}
    ]
  )

  def receipt_email(conn, %{id: id}) do
    with {:ok, email, mode} <-
           TerminalPayments.email_receipt(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(if(mode == :replayed, do: :ok, else: :accepted))
      |> json(%{email: email})
    end
  end

  operation(:sandbox_complete,
    summary: "Dev/test only: the sandbox terminal app takes or refuses the card",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: P.uuid()}],
    request_body: P.body(T.sandbox_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, T.terminal_payment())}]
  )

  def sandbox_complete(conn, %{id: id}) do
    with {:ok, payment} <-
           TerminalPayments.sandbox_complete(
             conn.assigns.tenant_context,
             id,
             conn.body_params.outcome,
             conn.body_params
             |> Map.take([:tip_cents, :surcharge_cents, :amount_cents])
             |> Map.reject(fn {_key, value} -> is_nil(value) end)
           ) do
      json(conn, %{payment: payment})
    end
  end
end
