defmodule PaleeWeb.MyShopController do
  @moduledoc """
  A member's side of a box's shop (ADR-190): browse the published catalog,
  price the basket (with whether online card payment is available), place
  an order for pickup, pay it online when a provider exists, cancel an
  unpaid order, and read their orders and shop transactions. Also the
  signed-in public catalog of a published box (`anyone` products).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.PublicBox
  alias Palee.Application.Shop.{Checkout, Fulfilment, MemberShop}
  alias PaleeWeb.Schemas.Shop, as: S
  alias PaleeWeb.ShopJSON
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Shop (member)"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id S.id_param()

  operation(:products,
    summary: "The box's shop: published products sold in the app",
    parameters: [
      %Parameter{name: :category, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Products", "application/json", S.many(:products, S.member_product())}]
  )

  def products(conn, params) do
    products = MemberShop.catalog(conn.assigns.tenant_context, %{category: params[:category]})
    json(conn, %{products: products})
  end

  operation(:product,
    summary: "One product of the box's shop",
    parameters: [@id],
    responses: [ok: {"Product", "application/json", S.one(:product, S.member_product())}]
  )

  def product(conn, %{id: id}) do
    with {:ok, product} <- MemberShop.product(conn.assigns.tenant_context, id) do
      json(conn, %{product: product})
    end
  end

  operation(:preview,
    summary: "Price the basket: lines, totals, pickup branches, payment modes and online_payment",
    request_body: S.body(S.cart_body()),
    responses: [ok: {"Preview", "application/json", S.preview()}]
  )

  def preview(conn, _params) do
    with {:ok, preview} <- Checkout.preview(conn.assigns.tenant_context, conn.body_params) do
      json(conn, preview)
    end
  end

  operation(:place_order,
    summary: "Place an order for pickup (stock is reserved; idempotent per idempotency_key)",
    request_body: S.body(S.checkout_body()),
    responses: [
      created: {"Order", "application/json", S.one(:order, S.order())},
      ok: {"Replayed", "application/json", S.one(:order, S.order())}
    ]
  )

  def place_order(conn, _params) do
    params =
      case get_req_header(conn, "idempotency-key") do
        [key | _] -> Map.put_new(conn.body_params, :idempotency_key, key)
        [] -> conn.body_params
      end

    with {:ok, order, outcome} <- Checkout.place_online(conn.assigns.tenant_context, params) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(%{order: ShopJSON.member_order(order)})
    end
  end

  operation(:orders,
    summary: "My orders at this box, newest first",
    responses: [ok: {"Orders", "application/json", S.many(:orders, S.order())}]
  )

  def orders(conn, _params) do
    orders = MemberShop.my_orders(conn.assigns.tenant_context)
    json(conn, %{orders: Enum.map(orders, &ShopJSON.member_order/1)})
  end

  operation(:order,
    summary: "One of my orders",
    parameters: [@id],
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def order(conn, %{id: id}) do
    with {:ok, order} <- MemberShop.my_order(conn.assigns.tenant_context, id) do
      json(conn, %{order: ShopJSON.member_order(order)})
    end
  end

  operation(:pay,
    summary:
      "Pay an unpaid order online (409 online_payment_unavailable until a provider exists)",
    parameters: [@id],
    request_body: S.body(S.pay_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def pay(conn, %{id: id}) do
    with {:ok, order} <- Checkout.pay_online(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.member_order(order)})
    end
  end

  operation(:cancel,
    summary: "Cancel my unpaid order",
    parameters: [@id],
    request_body: S.body(S.cancel_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def cancel(conn, %{id: id}) do
    with {:ok, order} <- Fulfilment.cancel_mine(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.member_order(order)})
    end
  end

  operation(:transactions,
    summary: "My shop transactions at this box (orders with their invoice, payments and refunds)",
    responses: [ok: {"Transactions", "application/json", S.many(:transactions, S.transaction())}]
  )

  def transactions(conn, _params) do
    context = conn.assigns.tenant_context
    json(conn, %{transactions: MemberShop.billing_transactions(context, context.user_id)})
  end

  operation(:public_products,
    summary: "A published box's shop products for anyone (signed in)",
    parameters: [
      %Parameter{name: :slug, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Products", "application/json", S.many(:products, S.member_product())}]
  )

  def public_products(conn, %{slug: slug}) do
    with {:ok, _box, %{organization_id: organization_id}} <- PublicBox.resolve(slug) do
      json(conn, %{products: MemberShop.public_catalog(organization_id)})
    end
  end
end
