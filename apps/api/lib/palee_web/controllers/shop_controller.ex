defmodule PaleeWeb.ShopController do
  @moduledoc """
  The staff side of the e-shop (ADR-190): catalog, stock, orders, the desk
  sale (Ταμείο), the check-in "order ready" query, and the Finance lineage
  of shop money. Capabilities: `manage_shop` (catalog, stock, refunds) and
  `sell_shop` (orders, desk sales), see `PaleeWeb.RouteCapabilities`.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.Shop.{Checkout, Fulfilment, ManageCatalog, ManageStock, PromoteProduct}
  alias Palee.{Finance, Organizations, Shop}
  alias PaleeWeb.Schemas.Shop, as: S
  alias PaleeWeb.ShopJSON
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Shop"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @id S.id_param()
  @variant_id S.id_param(:variant_id)

  # ── Catalog ──────────────────────────────────────────────────────────────

  operation(:products,
    summary: "Products with their variants and stock (drafts and published; archived on request)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["draft", "published", "archived"]}
      },
      %Parameter{name: :q, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :category, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Products", "application/json", S.many(:products, S.product())}]
  )

  def products(conn, params) do
    filters =
      %{q: params[:q], category: params[:category]}
      |> then(fn filters ->
        case params[:status] do
          nil -> filters
          status -> Map.put(filters, :statuses, [String.to_existing_atom(status)])
        end
      end)

    products = ManageCatalog.list(conn.assigns.tenant_context, filters)
    json(conn, %{products: Enum.map(products, &ShopJSON.product/1)})
  end

  operation(:create_product,
    summary: "Create a draft product with its variants (and optional opening stock)",
    request_body: S.body(S.product_body()),
    responses: [created: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def create_product(conn, _params) do
    with {:ok, product} <- ManageCatalog.create(conn.assigns.tenant_context, conn.body_params) do
      conn |> put_status(:created) |> json(%{product: ShopJSON.product(product)})
    end
  end

  operation(:product,
    summary: "One product",
    parameters: [@id],
    responses: [ok: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def product(conn, %{id: id}) do
    with {:ok, product} <- ManageCatalog.get(conn.assigns.tenant_context, id) do
      json(conn, %{product: ShopJSON.product(product)})
    end
  end

  operation(:update_product,
    summary: "Edit a product's details, photos, options, channels and branches",
    parameters: [@id],
    request_body: S.body(S.product_update_body()),
    responses: [ok: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def update_product(conn, %{id: id}) do
    with {:ok, product} <- ManageCatalog.update(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{product: ShopJSON.product(product)})
    end
  end

  operation(:set_product_status,
    summary: "Publish, unpublish (draft) or archive a product",
    description:
      "Publishing for `anyone` is a going-live action: a demo business answers 403 business_not_activated.",
    parameters: [@id],
    request_body: S.body(S.status_body()),
    responses: [ok: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def set_product_status(conn, %{id: id}) do
    with {:ok, product} <-
           ManageCatalog.set_status(conn.assigns.tenant_context, id, conn.body_params.status) do
      json(conn, %{product: ShopJSON.product(product)})
    end
  end

  operation(:create_variant,
    summary: "Add a variant (one value per option)",
    parameters: [@id],
    request_body: S.body(S.variant_body()),
    responses: [created: {"Variant", "application/json", S.one(:variant, S.variant())}]
  )

  def create_variant(conn, %{id: id}) do
    with {:ok, variant} <-
           ManageCatalog.save_variant(conn.assigns.tenant_context, id, nil, conn.body_params) do
      conn |> put_status(:created) |> json(%{variant: ShopJSON.variant(variant)})
    end
  end

  operation(:update_variant,
    summary: "Edit a variant; every price change is recorded in the price history",
    parameters: [@id, @variant_id],
    request_body: S.body(S.variant_body()),
    responses: [ok: {"Variant", "application/json", S.one(:variant, S.variant())}]
  )

  def update_variant(conn, %{id: id, variant_id: variant_id}) do
    with {:ok, variant} <-
           ManageCatalog.save_variant(
             conn.assigns.tenant_context,
             id,
             variant_id,
             conn.body_params
           ) do
      json(conn, %{variant: ShopJSON.variant(variant)})
    end
  end

  operation(:archive_variant,
    summary: "Archive a variant (kept on past orders)",
    parameters: [@id, @variant_id],
    responses: [ok: {"Variant", "application/json", S.one(:variant, S.variant())}]
  )

  def archive_variant(conn, %{id: id, variant_id: variant_id}) do
    with {:ok, variant} <-
           ManageCatalog.archive_variant(conn.assigns.tenant_context, id, variant_id) do
      json(conn, %{variant: ShopJSON.variant(variant)})
    end
  end

  # ── «Προώθηση» ───────────────────────────────────────────────────────────

  operation(:promote,
    summary:
      "Promote a product with a club post (#ανακοινώσεις, a group or squad, or the public feed), optionally with a promotion code",
    parameters: [@id],
    request_body: S.body(S.promote_body()),
    responses: [
      created:
        {"Post", "application/json",
         %Schema{
           type: :object,
           properties: %{
             post: PaleeWeb.Schemas.Community.post(),
             promotion_code: %{S.promotion_code() | nullable: true}
           },
           required: [:post]
         }}
    ]
  )

  def promote(conn, %{id: id}) do
    with {:ok, %{post: post, promotion_code: code}} <-
           PromoteProduct.promote(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{post: post, promotion_code: code && ShopJSON.promotion_code(code)})
    end
  end

  operation(:promotion_codes,
    summary: "Promotion codes, with their redemptions and status",
    parameters: [
      %Parameter{name: :product_id, in: :query, required: false, schema: S.uuid()}
    ],
    responses: [ok: {"Codes", "application/json", S.many(:promotion_codes, S.promotion_code())}]
  )

  def promotion_codes(conn, params) do
    codes =
      PromoteProduct.list_codes(conn.assigns.tenant_context, %{product_id: params[:product_id]})

    json(conn, %{promotion_codes: Enum.map(codes, &ShopJSON.promotion_code/1)})
  end

  operation(:update_promotion_code,
    summary: "Change a promotion code's discount, window or cap, or switch it off",
    parameters: [@id],
    request_body: S.body(S.promotion_code_update_body()),
    responses: [ok: {"Code", "application/json", S.one(:promotion_code, S.promotion_code())}]
  )

  def update_promotion_code(conn, %{id: id}) do
    with {:ok, code} <-
           PromoteProduct.update_code(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{promotion_code: ShopJSON.promotion_code(code)})
    end
  end

  # ── Stock ────────────────────────────────────────────────────────────────

  operation(:movements,
    summary: "A variant's stock ledger, newest first",
    parameters: [@id],
    responses: [ok: {"Movements", "application/json", S.many(:movements, S.movement())}]
  )

  def movements(conn, %{id: id}) do
    with {:ok, rows} <- ManageStock.ledger(conn.assigns.tenant_context, id) do
      json(conn, %{movements: Enum.map(rows, &ShopJSON.movement/1)})
    end
  end

  operation(:record_movement,
    summary: "Receive, adjust (with a reason), recount or transfer a variant's stock",
    parameters: [@id],
    request_body: S.body(S.movement_body()),
    responses: [
      created:
        {"Recorded", "application/json",
         %Schema{
           type: :object,
           properties: %{
             variant: S.variant(),
             movements: %Schema{type: :array, items: S.movement()}
           },
           required: [:variant, :movements]
         }}
    ]
  )

  def record_movement(conn, %{id: id}) do
    with {:ok, %{variant: variant, movements: rows}} <-
           ManageStock.record(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{
        variant: ShopJSON.variant(variant),
        movements: Enum.map(rows, &ShopJSON.movement/1)
      })
    end
  end

  # ── Orders ───────────────────────────────────────────────────────────────

  operation(:orders,
    summary: "Orders collected at the acting staff member's branches, newest first",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ["placed", "ready_for_pickup", "picked_up", "cancelled"]
        }
      },
      %Parameter{name: :user_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{
        name: :location_ids,
        in: :query,
        required: false,
        schema: %Schema{type: :string, description: "Comma-separated branch ids"}
      }
    ],
    responses: [ok: {"Orders", "application/json", S.many(:orders, S.order())}]
  )

  def orders(conn, params) do
    filters =
      %{user_id: params[:user_id]}
      |> maybe_put(:statuses, params[:status] && [String.to_existing_atom(params[:status])])
      |> maybe_put(:location_ids, location_ids(params))

    orders = Fulfilment.list(conn.assigns.tenant_context, filters)
    json(conn, %{orders: Enum.map(orders, &ShopJSON.staff_order/1)})
  end

  operation(:order,
    summary: "One order",
    parameters: [@id],
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def order(conn, %{id: id}) do
    with {:ok, order} <- Fulfilment.get(conn.assigns.tenant_context, id) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:lineage,
    summary: "The Finance rows and stock movements of an order (revenue lineage drill-down)",
    parameters: [@id],
    responses: [ok: {"Lineage", "application/json", S.lineage()}]
  )

  def lineage(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with {:ok, order} <- Fulfilment.get(context, id) do
      order_rows = Finance.revenue_lineage(context, Shop.order_source_type(), order.id)

      invoice_lines =
        Enum.flat_map(order.lines, fn line ->
          Finance.revenue_lineage(context, Shop.line_source_type(), line.id).invoice_lines
        end)

      json(conn, %{
        order: ShopJSON.staff_order(order),
        invoice_lines: invoice_lines,
        payments: order_rows.payments,
        reversals: order_rows.reversals,
        movements:
          context
          |> Shop.list_movements(%{order_id: order.id, limit: 1_000})
          |> Enum.map(&ShopJSON.movement/1)
      })
    end
  end

  operation(:mark_ready,
    summary: "Ready for pickup (the member is told where to collect it)",
    parameters: [@id],
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def mark_ready(conn, %{id: id}) do
    with {:ok, order} <- Fulfilment.mark_ready(conn.assigns.tenant_context, id) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:record_payment,
    summary: "Record the payment of an unpaid order at the desk",
    parameters: [@id],
    request_body: S.body(S.payment_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def record_payment(conn, %{id: id}) do
    with {:ok, order} <-
           Fulfilment.record_payment(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:pick_up,
    summary: "Hand the order over (with payment_method, an unpaid order is paid first)",
    parameters: [@id],
    request_body: S.body(S.pickup_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def pick_up(conn, %{id: id}) do
    with {:ok, order} <- Fulfilment.pick_up(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:cancel,
    summary: "Cancel an unpaid order (its stock is released and its invoice voided)",
    parameters: [@id],
    request_body: S.body(S.cancel_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def cancel(conn, %{id: id}) do
    with {:ok, order} <- Fulfilment.cancel(conn.assigns.tenant_context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:refund,
    summary: "Refund lines of a paid order (Finance reversal, refund receipt, optional restock)",
    parameters: [@id],
    request_body: S.body(S.refund_body()),
    responses: [
      ok:
        {"Refunded", "application/json",
         %Schema{
           type: :object,
           properties: %{
             order: S.order(),
             refund: %Schema{type: :object, additionalProperties: true}
           },
           required: [:order, :refund]
         }}
    ]
  )

  def refund(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with :ok <- require_capability(context, :take_payments),
         {:ok, %{order: order, reversal: reversal}} <-
           Fulfilment.refund(context, id, conn.body_params) do
      json(conn, %{order: ShopJSON.staff_order(order), refund: Map.drop(reversal, [:replayed])})
    end
  end

  operation(:set_fiscal_receipt,
    summary: "Record the legal receipt reference (myDATA MARK or register receipt) of an order",
    parameters: [@id],
    request_body: S.body(S.fiscal_receipt_body()),
    responses: [ok: {"Order", "application/json", S.one(:order, S.order())}]
  )

  def set_fiscal_receipt(conn, %{id: id}) do
    context = conn.assigns.tenant_context
    ref = conn.body_params.fiscal_receipt_ref

    with {:ok, order} <- Fulfilment.get(context, id),
         :ok <- fiscal_on_invoice(context, order, ref),
         {:ok, order} <- Shop.update_order(context, order.id, %{fiscal_receipt_ref: ref}) do
      json(conn, %{order: ShopJSON.staff_order(order)})
    end
  end

  defp fiscal_on_invoice(_context, %{finance_invoice_id: nil}, _ref), do: :ok

  defp fiscal_on_invoice(context, order, ref) do
    with {:ok, _invoice} <-
           Finance.set_fiscal_receipt_ref(context, order.finance_invoice_id, ref),
         do: :ok
  end

  operation(:desk_sale,
    summary: "A desk sale (Ταμείο) to a member or a walk-in, paid and handed over at once",
    request_body: S.body(S.desk_sale_body()),
    responses: [
      created: {"Order", "application/json", S.one(:order, S.order())},
      ok: {"Replayed", "application/json", S.one(:order, S.order())}
    ]
  )

  def desk_sale(conn, _params) do
    params = with_header_key(conn)

    with {:ok, order, outcome} <- Checkout.desk_sale(conn.assigns.tenant_context, params) do
      conn
      |> put_status(if(outcome == :created, do: :created, else: :ok))
      |> json(%{order: ShopJSON.staff_order(order)})
    end
  end

  operation(:ready_orders,
    summary: "A member's orders ready for pickup (the check-in desk's «παραγγελία έτοιμη»)",
    parameters: [
      %Parameter{name: :user_id, in: :query, required: true, schema: S.uuid()},
      %Parameter{name: :location_id, in: :query, required: false, schema: S.uuid()}
    ],
    responses: [ok: {"Orders", "application/json", S.many(:orders, S.order())}]
  )

  def ready_orders(conn, %{user_id: user_id} = params) do
    orders =
      Fulfilment.ready_for_member(conn.assigns.tenant_context, user_id, params[:location_id])

    json(conn, %{orders: Enum.map(orders, &ShopJSON.staff_order/1)})
  end

  # ── Finance ──────────────────────────────────────────────────────────────

  operation(:revenue_streams,
    summary:
      "Paid, refunded and net revenue per stream (membership, package, event, shop, other)",
    parameters: [
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      }
    ],
    responses: [ok: {"Streams", "application/json", S.revenue_streams()}]
  )

  # Business-wide, like the accounting exports (ADR-186 §7).
  def revenue_streams(conn, params) do
    context = conn.assigns.tenant_context
    today = Organizations.local_today(context.organization_id)
    to = params[:to] || today
    from = params[:from] || Date.beginning_of_month(to)

    with :ok <- Organizations.authorize_location(context, nil) do
      json(conn, %{from: from, to: to, streams: Finance.revenue_by_stream(context, from, to)})
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp require_capability(context, capability) do
    if Organizations.can?(context, capability), do: :ok, else: {:error, :forbidden}
  end

  defp with_header_key(conn) do
    case get_req_header(conn, "idempotency-key") do
      [key | _] -> Map.put_new(conn.body_params, :idempotency_key, key)
      [] -> conn.body_params
    end
  end

  defp location_ids(%{location_ids: ids}) when is_binary(ids) and ids != "",
    do: String.split(ids, ",", trim: true)

  defp location_ids(_params), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
