defmodule PaleeWeb.ShopController do
  @moduledoc """
  The staff side of the e-shop (ADR-190): catalog, stock, orders, the desk
  sale (Ταμείο), the check-in "order ready" query, and the Finance lineage
  of shop money. Capabilities: `manage_shop` (catalog, stock, refunds) and
  `sell_shop` (orders, desk sales), see `PaleeWeb.RouteCapabilities`.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{CompleteMediaUpload, RequestMediaUpload}

  alias Palee.Application.Shop.{
    Checkout,
    Fulfilment,
    ManageCatalog,
    ManageStock,
    ProductMedia,
    PromoteProduct
  }

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
    summary: "The console's catalog: one filter's products and the counts of every filter",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          enum: ["draft", "published", "archived", "low_stock"],
          description: "None: drafts and published"
        }
      },
      %Parameter{
        name: :q,
        in: :query,
        required: false,
        schema: %Schema{type: :string, description: "Title or category"}
      },
      %Parameter{name: :category, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :location_ids,
        in: :query,
        required: false,
        schema: %Schema{type: :string, description: "Comma-separated branch ids"}
      }
    ],
    responses: [ok: {"Products", "application/json", S.product_list()}]
  )

  def products(conn, params) do
    context = conn.assigns.tenant_context

    %{products: products, counts: counts} =
      ManageCatalog.list_view(context, %{
        status: params[:status],
        q: params[:q],
        category: params[:category],
        location_ids: location_ids(params)
      })

    json(conn, %{products: products_json(context, products), counts: counts})
  end

  defp products_json(context, products),
    do: context |> ProductMedia.attach(products) |> Enum.map(&ShopJSON.product/1)

  defp product_json(context, product), do: ShopJSON.product(ProductMedia.attach(context, product))

  operation(:create_product,
    summary: "Create a draft product with its variants (and optional opening stock)",
    request_body: S.body(S.product_body()),
    responses: [created: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def create_product(conn, _params) do
    context = conn.assigns.tenant_context

    with {:ok, product} <- ManageCatalog.create(context, conn.body_params) do
      conn |> put_status(:created) |> json(%{product: product_json(context, product)})
    end
  end

  operation(:product,
    summary: "One product",
    parameters: [@id],
    responses: [ok: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def product(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with {:ok, product} <- ManageCatalog.get(context, id) do
      json(conn, %{product: product_json(context, product)})
    end
  end

  operation(:update_product,
    summary:
      "Edit a product's details, photos, options, channels and branches, and optionally its status and its variants, in one transaction",
    parameters: [@id],
    request_body: S.body(S.product_update_body()),
    responses: [ok: {"Product", "application/json", S.one(:product, S.product())}]
  )

  def update_product(conn, %{id: id}) do
    context = conn.assigns.tenant_context

    with {:ok, product} <- ManageCatalog.update(context, id, conn.body_params) do
      json(conn, %{product: product_json(context, product)})
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
    context = conn.assigns.tenant_context

    with {:ok, product} <- ManageCatalog.set_status(context, id, conn.body_params.status) do
      json(conn, %{product: product_json(context, product)})
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
             post_id: S.uuid(),
             promotion_code_id: %{S.uuid() | nullable: true},
             post: PaleeWeb.Schemas.Community.post(),
             promotion_code: %{S.promotion_code() | nullable: true}
           },
           required: [:post_id, :post]
         }}
    ]
  )

  def promote(conn, %{id: id}) do
    with {:ok, %{post: post, promotion_code: code}} <-
           PromoteProduct.promote(conn.assigns.tenant_context, id, conn.body_params) do
      conn
      |> put_status(:created)
      |> json(%{
        post_id: post.id,
        promotion_code_id: code && code.id,
        post: post,
        promotion_code: code && ShopJSON.promotion_code(code)
      })
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

  # ── Photos ───────────────────────────────────────────────────────────────

  operation(:photo_upload,
    summary: "Reserve a product photo (shop_product_photo) and get a presigned upload for it",
    request_body: S.body(PaleeWeb.Schemas.Media.upload_request()),
    responses: [ok: {"Upload", "application/json", PaleeWeb.Schemas.Media.upload()}]
  )

  def photo_upload(conn, _params) do
    with {:ok, upload} <-
           RequestMediaUpload.call(
             conn.assigns.tenant_context,
             "shop_product_photo",
             conn.body_params
           ) do
      json(conn, upload)
    end
  end

  operation(:complete_photo,
    summary: "Verify an uploaded product photo (type, size, no metadata) and mark it ready",
    parameters: [@id],
    responses: [ok: {"Media", "application/json", PaleeWeb.Schemas.Media.media_response()}]
  )

  def complete_photo(conn, %{id: id}) do
    with {:ok, media} <-
           CompleteMediaUpload.call(conn.assigns.tenant_context, "shop_product_photo", id) do
      json(conn, %{media: media})
    end
  end

  # ── Payment methods ──────────────────────────────────────────────────────

  operation(:payment_methods,
    summary:
      "Ways to pay, from the payment port: desk methods staff record, and the online card (available: false until Palee has a card vendor)",
    responses: [ok: {"Methods", "application/json", S.many(:payment_methods, S.payment_method())}]
  )

  def payment_methods(conn, _params) do
    methods =
      conn.assigns.tenant_context
      |> Shop.payment_methods()
      |> Enum.map(&(&1 |> Map.put(:id, &1.method) |> Map.delete(:method)))

    json(conn, %{payment_methods: methods})
  end

  # ── Stock ────────────────────────────────────────────────────────────────

  operation(:ledger,
    summary: "The stock ledger across every variant, newest first, one page at a time",
    parameters: [
      %Parameter{
        name: :location_ids,
        in: :query,
        required: false,
        schema: %Schema{type: :string, description: "Comma-separated branch ids"}
      },
      %Parameter{
        name: :kind,
        in: :query,
        required: false,
        schema: %Schema{
          type: :string,
          description:
            "Comma-separated kinds: receive, sale, refund_restock, adjustment, transfer, reserve, release"
        }
      },
      %Parameter{name: :variant_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{name: :product_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{
        name: :from,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time"}
      },
      %Parameter{
        name: :to,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :"date-time", description: "Exclusive"}
      },
      %Parameter{name: :cursor, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 200}
      }
    ],
    responses: [ok: {"Ledger", "application/json", S.ledger()}]
  )

  def ledger(conn, params) do
    with {:ok, kinds} <- kinds(params[:kind]),
         {:ok, page} <-
           ManageStock.ledger_page(conn.assigns.tenant_context, %{
             location_ids: location_ids(params),
             kinds: kinds,
             variant_id: params[:variant_id],
             product_id: params[:product_id],
             from: params[:from],
             to: params[:to],
             cursor: params[:cursor],
             limit: params[:limit]
           }) do
      json(conn, %{
        movements: Enum.map(page.movements, &ShopJSON.ledger_movement/1),
        next_cursor: page.next_cursor
      })
    end
  end

  defp kinds(nil), do: {:ok, nil}

  defp kinds(text) do
    names = String.split(text, ",", trim: true)
    known = Shop.movement_kinds()

    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      case Enum.find(known, &(Atom.to_string(&1) == name)) do
        nil -> {:halt, {:error, :invalid_movement}}
        kind -> {:cont, {:ok, [kind | acc]}}
      end
    end)
  end

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
    summary:
      "Orders collected at the acting staff member's branches, newest first, with the count of every status",
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
      },
      %Parameter{
        name: :pickup_code,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 16}
      },
      %Parameter{
        name: :paid,
        in: :query,
        required: false,
        schema: %Schema{
          type: :boolean,
          description: "Only orders with money kept (paid, or partly refunded)"
        }
      },
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 500}
      }
    ],
    responses: [ok: {"Orders", "application/json", S.order_list()}]
  )

  def orders(conn, params) do
    filters =
      %{user_id: params[:user_id], limit: params[:limit] || 200}
      |> maybe_put(:statuses, params[:status] && [String.to_existing_atom(params[:status])])
      |> maybe_put(:location_ids, location_ids(params))
      |> maybe_put(:paid, if(params[:paid] == true, do: true))
      |> maybe_put(
        :pickup_code,
        params[:pickup_code] && Shop.normalize_pickup_code(params[:pickup_code])
      )

    %{orders: orders, counts: counts} = Fulfilment.list_view(conn.assigns.tenant_context, filters)
    json(conn, %{orders: Enum.map(orders, &ShopJSON.staff_order/1), counts: counts})
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
    summary:
      "Orders ready for pickup for a member, or for the pickup code they show (the check-in desk's «παραγγελία έτοιμη»)",
    parameters: [
      %Parameter{name: :user_id, in: :query, required: false, schema: S.uuid()},
      %Parameter{
        name: :pickup_code,
        in: :query,
        required: false,
        schema: %Schema{type: :string, maxLength: 16}
      },
      %Parameter{name: :location_id, in: :query, required: false, schema: S.uuid()}
    ],
    responses: [ok: {"Orders", "application/json", S.many(:orders, S.order())}]
  )

  def ready_orders(conn, params) do
    who =
      case params do
        %{pickup_code: code} when is_binary(code) -> {:pickup_code, code}
        %{user_id: user_id} when is_binary(user_id) -> user_id
        _neither -> nil
      end

    if who do
      orders = Fulfilment.ready_for_member(conn.assigns.tenant_context, who, params[:location_id])
      json(conn, %{orders: Enum.map(orders, &ShopJSON.staff_order/1)})
    else
      {:error, :buyer_required}
    end
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
