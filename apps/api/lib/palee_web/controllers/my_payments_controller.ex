defmodule PaleeWeb.MyPaymentsController do
  @moduledoc """
  Member › paying online (ADR-246/247): pay an open invoice on the
  provider's page, come back, and manage saved cards.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.{Parameter, Schema}
  alias Palee.Application.Payments.{OnlinePayments, OnlineSales}
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
    with {:ok, payment} <-
           OnlinePayments.pay_invoice(conn.assigns.tenant_context, id, with_client(conn)) do
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

  # ── ADR-248: online sales ───────────────────────────────────────────────

  operation(:package_terms,
    summary: "What buying a package online costs, and the texts to agree to",
    parameters: [
      @id,
      %Parameter{
        name: :language,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["el", "en"]}
      },
      %Parameter{
        name: :book_slot_id,
        in: :query,
        required: false,
        description: "The class bought for: a drop-in or trial for it has no withdrawal",
        schema: P.uuid()
      }
    ],
    responses: [ok: {"Terms", "application/json", P.package_terms()}]
  )

  def package_terms(conn, %{id: id} = params) do
    with {:ok, terms} <-
           OnlineSales.package_terms(
             conn.assigns.tenant_context,
             id,
             params[:language],
             params[:book_slot_id]
           ) do
      json(conn, terms)
    end
  end

  operation(:buy_package,
    summary: "Buy a package on the payment provider's page (and book a class once paid)",
    description:
      "Where the law gives 14 days to withdraw, `start_now` must be true: the member asks " <>
        "for the package to start at once. `book_slot_id` books that class once the package is paid.",
    parameters: [@id],
    request_body: P.body(P.buy_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def buy_package(conn, %{id: id}) do
    with {:ok, payment} <-
           OnlineSales.buy_package(conn.assigns.tenant_context, id, with_client(conn)) do
      json(conn, %{payment: payment})
    end
  end

  operation(:withdraw,
    summary: "Withdraw from a package bought online within 14 days",
    description: "Gives back the price less the part already used, and ends the package.",
    parameters: [@id],
    responses: [ok: {"Withdrawal", "application/json", P.withdrawal()}]
  )

  def withdraw(conn, %{id: id}) do
    with {:ok, result} <- OnlineSales.withdraw(conn.assigns.tenant_context, id) do
      json(conn, result)
    end
  end

  operation(:pay_shop_order,
    summary: "Pay an unpaid shop order on the payment provider's page",
    parameters: [@id],
    request_body: P.body(P.shop_pay_body()),
    responses: [ok: {"Payment", "application/json", P.one(:payment, P.intent())}]
  )

  def pay_shop_order(conn, %{id: id}) do
    with {:ok, payment} <-
           OnlineSales.pay_shop_order(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{payment: payment})
    end
  end

  defp with_client(conn) do
    Map.merge(conn.body_params, %{
      ip: conn.remote_ip |> :inet.ntoa() |> to_string(),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    })
  end
end
