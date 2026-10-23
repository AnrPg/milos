defmodule Palee.Application.Shop.Checkout do
  @moduledoc """
  Buying (ADR-190): a member's online order for pickup, and a staff desk
  sale (Ταμείο) to a member or a walk-in.

  **Online order** (`place_online/2`), one transaction:
  order + lines (prices from the catalog, member discount applied) →
  `reserve` movements at the pickup branch (refused when stock is short:
  never oversold) → the Finance invoice with an open balance. Then:

    * `at_pickup` / `on_account`: the order waits; staff record the payment
      at the desk (`Fulfilment.record_payment/3` or at handover);
    * `online`: the payment provider captures it (`pay_online/3`). The mock
      provider reports `available: false` until Palee has a card vendor, and
      the checkout refuses `online` with `online_payment_unavailable`.

  **Desk sale** (`desk_sale/2`), one transaction: order handed over on the
  spot (`picked_up`), `sale` movements, the invoice and its payment (cash,
  card at the terminal, transfer, other).

  Both are idempotent: the client sends an `idempotency_key` (or the
  `Idempotency-Key` header); a retry returns the first order unchanged.
  A demo business (ADR-184) takes no payment from real people
  (`business_not_activated`), and a walk-in is never a mock person.
  """

  alias Palee.Application.GoLive
  alias Palee.Application.Shop.{ManageCatalog, Observability, OrderMoney}
  alias Palee.{Facility, Finance, Organizations, Shop}

  @doc """
  Prices a cart for the acting member without placing it: lines, totals,
  the pickup branches and payment modes on offer, and whether online card
  payment is available (`online_payment: %{available, reason}`).
  """
  def preview(context, params) do
    with {:ok, priced, catalog, terms} <- price(context, params, :online, context.user_id),
         {:ok, pickup} <-
           pickup_location(context, catalog, params[:pickup_location_id], :optional) do
      {:ok,
       Map.merge(priced, %{
         pickup_location_id: pickup,
         pickup_location_ids: pickup_options(context, catalog),
         payment_modes: payment_modes(context, terms),
         online_payment: online_payment(context)
       })}
    end
  end

  @doc "The online-payment flag the basket shows: `%{available, reason, provider}`."
  def online_payment(context) do
    context |> Shop.online_payment() |> Map.take([:available, :reason, :provider])
  end

  defp payment_modes(context, terms) do
    online = online_payment(context).available

    Enum.filter(Shop.online_modes(), fn
      :online -> online
      :on_account -> not is_nil(terms)
      :at_pickup -> true
    end)
  end

  @doc "Places the acting member's order (see the module doc)."
  def place_online(context, params) do
    with {:ok, key} <- idempotency_key(params, "online:" <> context.user_id) do
      case Shop.get_order_by_key(context, key) do
        %{} = order -> {:ok, order, :replayed}
        nil -> place_new_online(context, params, key)
      end
    end
  end

  defp place_new_online(context, params, key) do
    buyer = context.user_id
    now = DateTime.utc_now()

    with :ok <- GoLive.check_payment(context, buyer),
         {:ok, priced, catalog, terms} <- price(context, params, :online, buyer),
         {:ok, mode} <-
           Shop.checkout_mode(params[:payment_mode] || :at_pickup, %{
             online_available: online_payment(context).available,
             on_account_allowed: not is_nil(terms)
           }),
         {:ok, pickup} <-
           pickup_location(context, catalog, params[:pickup_location_id], :required),
         {:ok, order} <-
           Shop.transaction(context, fn ->
             create(context, %{
               order: %{
                 channel: :online,
                 status: :placed,
                 payment_status: :pending_payment,
                 payment_mode: mode,
                 user_id: buyer,
                 membership_id: terms && terms.membership_id,
                 pickup_location_id: pickup,
                 currency: priced.currency,
                 subtotal_cents: priced.subtotal_cents,
                 discount_cents: priced.discount_cents,
                 total_cents: priced.total_cents,
                 source: Shop.order_source(params[:source]),
                 source_ref_id: params[:source_ref_id],
                 promotion_code: params[:promotion_code],
                 note: params[:note],
                 idempotency_key: key,
                 placed_at: now,
                 expires_at: Shop.hold_until(now),
                 created_by_id: buyer
               },
               lines: priced.lines,
               stock: :reserve
             })
           end) do
      after_placed(context, order)

      Shop.notifier().order_placed(context, %{
        order_id: order.id,
        order_number: order.number,
        total_cents: order.total_cents,
        currency: order.currency
      })

      if mode == :online and is_binary(params[:payment_token]) do
        case pay_online(context, order.id, params) do
          {:ok, paid} -> {:ok, paid, :created}
          {:error, reason} -> {:error, {:payment_failed, reason, order}}
        end
      else
        {:ok, order, :created}
      end
    end
    |> unique_key_race(context, key)
  end

  @doc """
  Captures an unpaid online order through the payment provider and records
  the payment (idempotent: the capture key is the order's).
  """
  def pay_online(context, order_id, params) do
    with %{} = order <- Shop.get_order(context, order_id) || {:error, :not_found},
         true <- order.user_id == context.user_id || {:error, :not_found},
         true <- online_payment(context).available || {:error, :online_payment_unavailable} do
      case order.payment_status do
        :paid ->
          {:ok, order}

        :pending_payment ->
          capture_key = "capture:" <> order.id

          with {:ok, receipt} <-
                 Shop.payment_provider().capture(context, %{
                   order_id: order.id,
                   amount_cents: order.total_cents,
                   currency: order.currency,
                   idempotency_key: capture_key,
                   payment_token: params[:payment_token]
                 }),
               {:ok, paid} <-
                 Shop.transaction(context, fn ->
                   with %{} = locked <- Shop.get_order(context, order.id, lock: true),
                        {:ok, paid, _payment} <-
                          OrderMoney.settle(context, locked, :online, %{
                            provider: receipt.provider,
                            reference: receipt.reference,
                            idempotency_key: capture_key
                          }) do
                     {:ok, paid}
                   end
                 end) do
            Observability.order(:paid, context, paid)
            {:ok, paid}
          end

        _other ->
          {:error, :order_not_payable}
      end
    end
  end

  @doc """
  A staff desk sale. `params`: `lines`, `payment_method` (cash | card_manual |
  bank_transfer | other), optional `user_id` (a member) or `customer_name`
  (a walk-in), `location_id` (the desk's branch), `idempotency_key`.
  """
  def desk_sale(context, params) do
    with {:ok, key} <- idempotency_key(params, "pos:" <> context.user_id) do
      case Shop.get_order_by_key(context, key) do
        %{} = order -> {:ok, order, :replayed}
        nil -> new_desk_sale(context, params, key)
      end
    end
  end

  defp new_desk_sale(context, params, key) do
    buyer = params[:user_id]
    now = DateTime.utc_now()

    with :ok <- GoLive.check_payment(context, buyer),
         {:ok, method} <- Shop.desk_method(params[:payment_method]),
         {:ok, location} <- Organizations.desk_location(context, params[:location_id]),
         {:ok, priced, catalog, terms} <- price(context, params, :pos, buyer),
         {:ok, location} <- desk_covers(catalog, location),
         {:ok, order} <-
           Shop.transaction(context, fn ->
             with {:ok, order} <-
                    create(context, %{
                      order: %{
                        channel: :pos,
                        status: :picked_up,
                        payment_status: :pending_payment,
                        payment_mode: method,
                        user_id: buyer,
                        membership_id: terms && terms.membership_id,
                        customer_name: params[:customer_name],
                        pickup_location_id: location,
                        currency: priced.currency,
                        subtotal_cents: priced.subtotal_cents,
                        discount_cents: priced.discount_cents,
                        total_cents: priced.total_cents,
                        source: :desk,
                        promotion_code: params[:promotion_code],
                        note: params[:note],
                        idempotency_key: key,
                        placed_at: now,
                        created_by_id: context.user_id
                      },
                      lines: priced.lines,
                      stock: :sale
                    }),
                  {:ok, paid, _payment} <- OrderMoney.settle(context, order, method),
                  {:ok, paid} <-
                    Shop.update_order(context, paid.id, %{
                      picked_up_at: now,
                      handled_by_id: context.user_id
                    }) do
               {:ok, paid}
             end
           end) do
      after_placed(context, order)
      Observability.order(:paid, context, order)
      Observability.order(:picked_up, context, order)
      {:ok, order, :created}
    end
    |> unique_key_race(context, key)
  end

  # ── Shared ───────────────────────────────────────────────────────────────

  # Inside the transaction: order + lines, their stock movements, the invoice.
  defp create(context, %{order: order_attrs, lines: lines, stock: kind}) do
    line_attrs =
      Enum.map(
        lines,
        &Map.merge(Map.drop(&1, [:currency]), %{location_id: order_attrs.pickup_location_id})
      )

    today = Organizations.local_today(context.organization_id)

    with {:ok, order} <- Shop.insert_order(context, order_attrs, line_attrs),
         {:ok, %{movements: rows}} <-
           Shop.apply_movements(context, stock_movements(context, order, kind)),
         {:ok, order, _invoice} <- OrderMoney.invoice(context, order, today) do
      Observability.stock_moved(context, rows)
      {:ok, order}
    end
  end

  defp stock_movements(context, order, kind) do
    order.lines
    |> Enum.filter(&tracked?(context, &1.variant_id))
    |> Enum.map(fn line ->
      %{
        variant_id: line.variant_id,
        location_id: line.location_id,
        kind: kind,
        quantity: if(kind == :sale, do: -line.quantity, else: line.quantity),
        order_id: order.id,
        order_line_id: line.id,
        unit_cost_cents: line.cost_price_cents,
        user_id: context.user_id
      }
    end)
  end

  defp tracked?(context, variant_id) do
    case Shop.get_variant(context, variant_id) do
      %{track_inventory: false} -> false
      _tracked -> true
    end
  end

  defp after_placed(context, order) do
    Observability.order(:placed, context, order)

    order.lines
    |> Enum.map(& &1.variant_id)
    |> then(&Shop.refresh_stock_status(context, &1))
    |> then(&ManageCatalog.alert_stock(context, &1))
  end

  defp price(context, params, channel, buyer) do
    items = params[:lines] || params[:items] || []

    variant_ids =
      items
      |> Enum.map(&(Map.get(&1, :variant_id) || Map.get(&1, "variant_id")))
      |> Enum.filter(&is_binary/1)

    catalog = load_catalog(context, variant_ids)
    terms = buyer && Finance.member_shop_terms(context, buyer)

    already =
      if buyer do
        product_ids = catalog |> Map.values() |> Enum.map(& &1.product.id) |> Enum.uniq()
        Shop.units_held(context, buyer, product_ids)
      else
        %{}
      end

    with {:ok, priced} <-
           Shop.price_cart(items, catalog,
             channel: channel,
             member_discount_percent: terms && terms.member_discount_percent,
             already: already
           ) do
      {:ok, priced, catalog, terms}
    end
  end

  defp load_catalog(_context, []), do: %{}

  defp load_catalog(context, variant_ids) do
    variants = Shop.list_variants(context, %{ids: Enum.uniq(variant_ids)})

    products =
      Shop.list_products(context, %{ids: variants |> Enum.map(& &1.product_id) |> Enum.uniq()})

    by_id = Map.new(products, &{&1.id, &1})

    Map.new(variants, fn variant ->
      {variant.id, %{variant: variant, product: Map.fetch!(by_id, variant.product_id)}}
    end)
  end

  # The branch an online order is collected at: one every product is valid
  # at (ADR-186 §8 covering) and an active branch of the business.
  defp pickup_location(context, catalog, requested, mode) do
    options = pickup_options(context, catalog)

    cond do
      is_binary(requested) ->
        if requested in options,
          do: {:ok, requested},
          else: {:error, :pickup_location_not_available}

      options == [] and all_branches?(catalog) ->
        {:ok, nil}

      length(options) == 1 ->
        {:ok, hd(options)}

      mode == :optional ->
        {:ok, nil}

      options == [] ->
        {:error, :pickup_location_not_available}

      true ->
        {:error, :pickup_location_required}
    end
  end

  defp pickup_options(context, catalog) do
    active = context |> Facility.list_locations() |> Enum.map(& &1.id)

    catalog
    |> Map.values()
    |> Enum.map(&Palee.Application.CoveringBranches.of_row(&1.product))
    |> Enum.reduce(active, fn
      :all, acc -> acc
      ids, acc -> Enum.filter(acc, &(&1 in ids))
    end)
  end

  defp all_branches?(catalog),
    do:
      Enum.all?(
        Map.values(catalog),
        &(Palee.Application.CoveringBranches.of_row(&1.product) == :all)
      )

  defp desk_covers(catalog, location) do
    if Enum.all?(Map.values(catalog), fn %{product: product} ->
         case Palee.Application.CoveringBranches.of_row(product) do
           :all -> true
           ids -> location in ids
         end
       end),
       do: {:ok, location},
       else: {:error, :product_not_available}
  end

  defp idempotency_key(params, scope) do
    case params[:idempotency_key] do
      key when is_binary(key) and byte_size(key) >= 8 and byte_size(key) <= 120 ->
        {:ok, scope <> ":" <> key}

      _missing ->
        {:error, :idempotency_key_required}
    end
  end

  # Two identical requests raced past the lookup: the unique index let one
  # through; answer the other with that order.
  defp unique_key_race({:error, %Ecto.Changeset{errors: errors}} = error, context, key) do
    if Keyword.has_key?(errors, :idempotency_key) do
      case Shop.get_order_by_key(context, key) do
        nil -> error
        order -> {:ok, order, :replayed}
      end
    else
      error
    end
  end

  defp unique_key_race({:error, {:insufficient_stock, at}}, _context, _key),
    do: {:error, {:insufficient_stock, at}}

  defp unique_key_race(result, _context, _key), do: result
end
