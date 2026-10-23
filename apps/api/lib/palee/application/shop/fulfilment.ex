defmodule Palee.Application.Shop.Fulfilment do
  @moduledoc """
  After an order is placed (ADR-190): staff prepare it, take the payment,
  hand it over, cancel or refund it; the member cancels their own unpaid
  order; a sweep releases unpaid orders whose hold ran out; the check-in
  desk asks whether the person at the door has an order ready.

  Every change locks the order row (`FOR UPDATE`) and runs with its stock
  movements and Finance rows in one transaction:

    * handover (`pick_up/3`): `release` + `sale` per line (the reserved unit
      leaves the shelf), after the payment when it is taken at the desk;
    * cancel: `release` per line and the unpaid invoice is voided;
    * refund: the Finance reversal (it keeps the shop lineage), the lines'
      refunded quantities, and `refund_restock` for the units that go back
      on the shelf; an order refunded before pickup also releases them.

  Branch-scoped staff (ADR-186) act only on orders collected at their
  branches.
  """

  alias Palee.Application.Shop.{ManageCatalog, Observability, OrderMoney}
  alias Palee.{Identity, Organizations, Shop}

  @doc "Orders for the staff console (`filters`: states, user_id, location_ids, from)."
  def list(context, filters \\ %{}) do
    filters =
      case Organizations.location_scope(context) do
        :all -> filters
        ids -> Map.put(filters, :location_ids, restrict(filters[:location_ids], ids))
      end

    Shop.list_orders(context, filters)
  end

  defp restrict(nil, scope), do: scope
  defp restrict(requested, scope), do: Enum.filter(requested, &(&1 in scope))

  @doc "One order, when it is collected at one of the acting staff member's branches."
  def get(context, id) do
    with %{} = order <- Shop.get_order(context, id) || {:error, :not_found},
         :ok <- in_scope(context, order) do
      {:ok, order}
    end
  end

  @doc "Για ετοιμασία → Έτοιμη για παραλαβή: tells the member where to collect it."
  def mark_ready(context, id) do
    with {:ok, order} <-
           change(context, id, fn order ->
             with {:ok, attrs} <-
                    Shop.order_transition(order, :mark_ready, %{
                      at: DateTime.utc_now(),
                      by: context.user_id
                    }) do
               Shop.update_order(context, order.id, attrs)
             end
           end) do
      Observability.order(:ready, context, order)

      Shop.notifier().order_ready(context, %{
        user_id: order.user_id,
        order_id: order.id,
        order_number: order.number,
        pickup_location_id: order.pickup_location_id
      })

      {:ok, order}
    end
  end

  @doc "Records the payment of an unpaid order at the desk (cash, card at the terminal, ...)."
  def record_payment(context, id, params) do
    with {:ok, method} <- Shop.desk_method(params[:payment_method]),
         :ok <- Palee.Application.GoLive.check_payment(context, order_user(context, id)),
         {:ok, order} <-
           change(context, id, fn order ->
             with {:ok, paid, _payment} <- OrderMoney.settle(context, order, method),
                  do: {:ok, paid}
           end) do
      Observability.order(:paid, context, order)
      {:ok, order}
    end
  end

  @doc """
  Παραδόθηκε: hands the order over. With `payment_method` an unpaid order is
  paid first, in the same transaction.
  """
  def pick_up(context, id, params \\ %{}) do
    method = params[:payment_method]

    with :ok <- maybe_go_live(context, id, method),
         {:ok, %{order: order, paid?: paid?, rows: rows}} <-
           change_with(context, id, fn order ->
             with {:ok, order, paid?} <- maybe_settle(context, order, method),
                  {:ok, attrs} <-
                    Shop.order_transition(order, :pick_up, %{
                      at: DateTime.utc_now(),
                      by: context.user_id
                    }),
                  {:ok, %{movements: rows}} <-
                    Shop.apply_movements(context, handover(context, order)),
                  {:ok, order} <- Shop.update_order(context, order.id, attrs) do
               {:ok, %{order: order, paid?: paid?, rows: rows}}
             end
           end) do
      if paid?, do: Observability.order(:paid, context, order)
      Observability.order(:picked_up, context, order)
      Observability.stock_moved(context, rows)
      refresh(context, order)
      {:ok, order}
    end
  end

  defp maybe_go_live(_context, _id, nil), do: :ok

  defp maybe_go_live(context, id, _method),
    do: Palee.Application.GoLive.check_payment(context, order_user(context, id))

  defp maybe_settle(_context, %{payment_status: :paid} = order, _method), do: {:ok, order, false}
  defp maybe_settle(_context, order, nil), do: {:ok, order, false}

  defp maybe_settle(context, order, method) do
    with {:ok, method} <- Shop.desk_method(method),
         {:ok, paid, _payment} <- OrderMoney.settle(context, order, method) do
      {:ok, paid, true}
    end
  end

  defp handover(context, order) do
    reserved = reserved_lines(context, order)

    Enum.flat_map(order.lines, fn line ->
      if MapSet.member?(reserved, line.id) do
        base = %{
          variant_id: line.variant_id,
          location_id: line.location_id,
          order_id: order.id,
          order_line_id: line.id,
          user_id: context.user_id,
          unit_cost_cents: line.cost_price_cents
        }

        [
          Map.merge(base, %{kind: :release, quantity: line.quantity}),
          Map.merge(base, %{kind: :sale, quantity: -line.quantity})
        ]
      else
        []
      end
    end)
  end

  # The lines whose units are still held by a reservation (not released).
  defp reserved_lines(context, order) do
    context
    |> Shop.list_movements(%{order_id: order.id, kinds: [:reserve, :release], limit: 1_000})
    |> Enum.group_by(& &1.order_line_id)
    |> Enum.filter(fn {_line, rows} ->
      Enum.sum(Enum.map(rows, &if(&1.kind == :reserve, do: &1.quantity, else: -&1.quantity))) > 0
    end)
    |> MapSet.new(&elem(&1, 0))
  end

  @doc "Cancels an unpaid order (staff); the stock goes back and the invoice is voided."
  def cancel(context, id, params \\ %{}) do
    with {:ok, order} <- do_cancel(context, id, params[:reason]) do
      {:ok, order}
    end
  end

  @doc "The member cancels their own unpaid order."
  def cancel_mine(context, id, params \\ %{}) do
    with %{} = order <- Shop.get_order(context, id) || {:error, :not_found},
         true <- order.user_id == context.user_id || {:error, :not_found} do
      do_cancel(context, order.id, params[:reason] || "cancelled_by_member", skip_scope: true)
    end
  end

  defp do_cancel(context, id, reason, opts \\ []) do
    with {:ok, %{order: order, rows: rows}} <-
           change_with(
             context,
             id,
             fn order ->
               with {:ok, attrs} <-
                      Shop.order_transition(order, :cancel, %{
                        at: DateTime.utc_now(),
                        by: context.user_id,
                        reason: reason
                      }),
                    {:ok, %{movements: rows}} <-
                      Shop.apply_movements(context, releases(context, order)),
                    :ok <- OrderMoney.void(context, order, reason),
                    {:ok, order} <- Shop.update_order(context, order.id, attrs) do
                 {:ok, %{order: order, rows: rows}}
               end
             end,
             opts
           ) do
      Observability.order(:cancelled, context, order, %{metadata: %{reason: reason}})
      Observability.stock_moved(context, rows)
      refresh(context, order)
      {:ok, order}
    end
  end

  defp releases(context, order) do
    reserved = reserved_lines(context, order)

    order.lines
    |> Enum.filter(&MapSet.member?(reserved, &1.id))
    |> Enum.map(fn line ->
      %{
        variant_id: line.variant_id,
        location_id: line.location_id,
        kind: :release,
        quantity: line.quantity,
        order_id: order.id,
        order_line_id: line.id,
        user_id: context.user_id
      }
    end)
  end

  @doc """
  Refunds lines of a paid order: `lines: [%{order_line_id, quantity,
  restock}]`, `reason`, `idempotency_key`. The money comes back through
  Finance (stream `shop`, same source), with the member's refund receipt.
  """
  def refund(context, id, params) do
    with {:ok, key} <- refund_key(params, id),
         {:ok, %{order: order, reversal: reversal, rows: rows}} <-
           change_with(context, id, fn order ->
             refund_in_transaction(context, order, params, key)
           end) do
      unless Map.get(reversal, :replayed) do
        Observability.order(:refunded, context, order, %{
          amount_cents: reversal.amount_cents,
          metadata: %{finance_payment_reversal_id: reversal.id}
        })

        Observability.stock_moved(context, rows)
        refresh(context, order)
      end

      {:ok, %{order: order, reversal: reversal}}
    end
  end

  defp refund_in_transaction(context, order, params, key) do
    with {:ok, allocations, amount} <- Shop.allocate_refund(order.lines, params[:lines]),
         {:ok, refunded, reversal} <-
           OrderMoney.refund(context, order, amount, %{
             reason: params[:reason],
             idempotency_key: key,
             receipt_party: receipt_party(context, order),
             order_line_ids: Enum.map(allocations, & &1.line.id)
           }) do
      if Map.get(reversal, :replayed) do
        {:ok, %{order: refunded, reversal: reversal, rows: []}}
      else
        with :ok <- mark_lines(context, allocations),
             {:ok, %{movements: rows}} <-
               Shop.apply_movements(context, refund_movements(context, order, allocations)) do
          {:ok, %{order: Shop.get_order(context, order.id), reversal: reversal, rows: rows}}
        end
      end
    end
  end

  defp mark_lines(context, allocations) do
    Enum.reduce_while(allocations, :ok, fn %{line: line, quantity: quantity, cents: cents}, :ok ->
      case Shop.update_order_line(context, line.id, %{
             refunded_quantity: line.refunded_quantity + quantity,
             refunded_cents: line.refunded_cents + cents
           }) do
        {:ok, _line} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # Before pickup the units are still reserved: they are released. After
  # pickup, the ones the staff put back on the shelf are restocked.
  defp refund_movements(context, order, allocations) do
    reserved = reserved_lines(context, order)

    Enum.flat_map(allocations, fn %{line: line, quantity: quantity, restock: restock} ->
      base = %{
        variant_id: line.variant_id,
        location_id: line.location_id,
        order_id: order.id,
        order_line_id: line.id,
        user_id: context.user_id
      }

      cond do
        MapSet.member?(reserved, line.id) ->
          [Map.merge(base, %{kind: :release, quantity: quantity})]

        restock ->
          [Map.merge(base, %{kind: :refund_restock, quantity: quantity})]

        true ->
          []
      end
    end)
  end

  defp refund_key(params, id) do
    case params[:idempotency_key] do
      key when is_binary(key) and byte_size(key) >= 8 -> {:ok, "shop_refund:#{id}:#{key}"}
      _missing -> {:error, :idempotency_key_required}
    end
  end

  defp receipt_party(context, order) do
    %{
      "organization_name" => get_in(context, [Access.key(:organization, %{}), Access.key(:name)]),
      "member_display_name" => member_name(order)
    }
  end

  defp member_name(%{user_id: nil, customer_name: name}), do: name

  defp member_name(%{user_id: user_id}) do
    case Identity.find_by_id(user_id) do
      %{display_nickname: name} when is_binary(name) and name != "" -> name
      %{nickname: name} -> name
      _missing -> nil
    end
  end

  @doc """
  Releases unpaid online orders whose hold ran out (ADR-190 default seven
  days). Returns the cancelled orders.
  """
  def expire_unpaid(context, now \\ DateTime.utc_now()) do
    context
    |> Shop.list_orders(%{
      channel: :online,
      statuses: [:placed, :ready_for_pickup],
      payment_statuses: [:pending_payment],
      expired_before: now,
      limit: 500
    })
    |> Enum.filter(&Shop.order_expired?(&1, now))
    |> Enum.flat_map(fn order ->
      case do_cancel(Map.put(context, :user_id, nil), order.id, "expired", skip_scope: true) do
        {:ok, cancelled} -> [cancelled]
        {:error, _reason} -> []
      end
    end)
  end

  @doc """
  The member's orders ready for pickup, for the check-in desk («έχει
  παραγγελία έτοιμη · Παράδοση»). Narrowed to the desk's branch when given.
  """
  def ready_for_member(context, user_id, location_id \\ nil) do
    context
    |> Shop.list_orders(%{user_id: user_id, statuses: [:ready_for_pickup]})
    |> Enum.filter(&(is_nil(location_id) or &1.pickup_location_id in [nil, location_id]))
    |> Enum.filter(&(in_scope(context, &1) == :ok))
  end

  # ── Locking ──────────────────────────────────────────────────────────────

  defp change(context, id, fun) do
    with {:ok, %{order: order}} <-
           change_with(context, id, fn order ->
             with {:ok, order} <- fun.(order), do: {:ok, %{order: order}}
           end),
         do: {:ok, order}
  end

  defp change_with(context, id, fun, opts \\ []) do
    Shop.transaction(context, fn ->
      with %{} = order <- Shop.get_order(context, id, lock: true) || {:error, :not_found},
           :ok <- if(opts[:skip_scope], do: :ok, else: in_scope(context, order)) do
        fun.(order)
      end
    end)
  end

  defp in_scope(context, order) do
    if Organizations.location_in_scope?(context, order.pickup_location_id),
      do: :ok,
      else: {:error, :not_found}
  end

  defp order_user(context, id) do
    case Shop.get_order(context, id) do
      %{user_id: user_id} -> user_id
      nil -> nil
    end
  end

  defp refresh(context, order) do
    order.lines
    |> Enum.map(& &1.variant_id)
    |> then(&Shop.refresh_stock_status(context, &1))
    |> then(&ManageCatalog.alert_stock(context, &1))
  end
end
