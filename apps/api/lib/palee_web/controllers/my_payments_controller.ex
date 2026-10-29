defmodule PaleeWeb.MyPaymentsController do
  @moduledoc """
  Member › paying online (ADR-246/247): pay an open invoice on the
  provider's page, come back, and manage saved cards.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Payments.OnlinePayments
  alias PaleeWeb.Schemas.Payments, as: P

  action_fallback PaleeWeb.FallbackController

  tags(["Member Finance"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id %Parameter{name: :id, in: :path, required: true, schema: P.uuid()}

  operation(:terms,
    summary:
      "What paying this invoice online costs, and the text to agree to when saving the card",
    parameters: [
      @id,
      %Parameter{
        name: :language,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["el", "en"]}
      }
    ],
    responses: [ok: {"Terms", "application/json", P.checkout_terms()}]
  )

  def terms(conn, %{id: id} = params) do
    with {:ok, terms} <-
           OnlinePayments.checkout_terms(conn.assigns.tenant_context, id, params[:language]) do
      json(conn, terms)
    end
  end

  operation(:pay,
    summary: "Pay an open invoice on the payment provider's page",
    description:
      "Returns the payment with `redirect_url`: send the member there. Saving the card " <>
        "needs `consent_accepted`.",
    parameters: [@id],
    request_body: P.body(P.pay_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def pay(conn, %{id: id}) do
    params =
      conn.body_params
      |> Map.merge(%{
        ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
        user_agent: conn |> get_req_header("user-agent") |> List.first()
      })

    with {:ok, payment} <- OnlinePayments.pay_invoice(conn.assigns.tenant_context, id, params) do
      json(conn, %{payment: payment})
    end
  end

  operation(:returned,
    summary: "Back from the provider's page: ask the provider about the payment now",
    request_body: P.body(P.return_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def returned(conn, _params) do
    with {:ok, payment} <- OnlinePayments.returned(conn.assigns.tenant_context, conn.body_params) do
      json(conn, %{payment: payment})
    end
  end

  operation(:show,
    summary: "One of my online payments",
    parameters: [@id],
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def show(conn, %{id: id}) do
    with {:ok, payment} <- OnlinePayments.my_payment(conn.assigns.tenant_context, id) do
      json(conn, %{payment: payment})
    end
  end

  operation(:methods,
    summary: "My saved cards",
    responses: [
      ok:
        {"Cards", "application/json",
         P.one(:payment_methods, %Schema{type: :array, items: P.method()})}
    ]
  )

  def methods(conn, _params),
    do: json(conn, %{payment_methods: OnlinePayments.my_methods(conn.assigns.tenant_context)})

  operation(:revoke_method,
    summary: "Withdraw my permission: the card is never charged again",
    parameters: [@id],
    responses: [ok: {"Card", "application/json", P.one(:payment_method, P.method())}]
  )

  def revoke_method(conn, %{id: id}) do
    with {:ok, method} <- OnlinePayments.revoke_my_method(conn.assigns.tenant_context, id) do
      json(conn, %{payment_method: method})
    end
  end

  operation(:set_autopay,
    summary: "Pay due invoices automatically with this card (one card at a time)",
    parameters: [@id],
    request_body: P.body(P.autopay_body()),
    responses: [ok: {"Card", "application/json", P.one(:payment_method, P.method())}]
  )

  def set_autopay(conn, %{id: id}) do
    with {:ok, method} <-
           OnlinePayments.set_autopay(conn.assigns.tenant_context, id, conn.body_params.autopay) do
      json(conn, %{payment_method: method})
    end
  end

  operation(:sandbox_complete,
    summary: "Dev and test only: finish a sandbox checkout as the provider's page would",
    request_body: P.body(P.sandbox_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def sandbox_complete(conn, _params) do
    with {:ok, payment} <-
           OnlinePayments.sandbox_complete(conn.assigns.tenant_context, conn.body_params) do
      json(conn, %{payment: payment})
    end
  end
end
