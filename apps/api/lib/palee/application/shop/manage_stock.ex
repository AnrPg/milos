defmodule Palee.Application.Shop.ManageStock do
  @moduledoc """
  Stock movements staff record by hand (ADR-190): a delivery (`receive`), an
  adjustment with its reason (damage, loss, return, other), a recount (the
  counted number; the adjustment is computed on the locked level), and a
  transfer between two branches. Sales, reservations, releases and refund
  restocks come from orders (`Shop.Checkout`, `Shop.Fulfilment`).

  Branch-scoped staff (ADR-186) move stock only at their branches; stock
  without a branch (a business with one stock) is for all-scoped staff.
  A status that gets worse (low, critical, out) alerts everyone with
  `manage_shop`.
  """

  alias Palee.Application.Shop.{ManageCatalog, Observability}
  alias Palee.{Identity, Organizations, Shop}

  @doc "Records one movement on a variant; returns the variant with its stock and the ledger rows."
  def record(context, variant_id, params) do
    params = normalize(params)

    with %{} = variant <- Shop.get_variant(context, variant_id) || {:error, :not_found},
         {:ok, _product} <- ManageCatalog.get(context, variant.product_id),
         {:ok, movements} <- movements(context, variant, params),
         :ok <- authorize(context, movements),
         {:ok, %{movements: rows}} <- Shop.apply_movements(context, movements) do
      Observability.stock_moved(context, rows)
      ManageCatalog.alert_stock(context, Shop.refresh_stock_status(context, [variant.id]))
      {:ok, %{variant: Shop.get_variant(context, variant.id), movements: rows}}
    else
      {:error, {reason, _at}} when is_atom(reason) -> {:error, reason}
      error -> error
    end
  end

  @max_page 200

  @doc """
  The stock ledger across every variant, newest first, one page at a time
  (keyset `cursor`, `limit` up to #{@max_page}). `filters`: `location_ids`
  (narrowed to the acting staff member's branches), `kinds`, `from`, `to`,
  `variant_id`, `product_id`. Each row names its product, variant, order
  number and who recorded it. Returns `%{movements, next_cursor}`.
  """
  def ledger_page(context, filters) do
    limit = min(max(filters[:limit] || 50, 1), @max_page)

    with {:ok, before} <- decode_cursor(filters[:cursor]) do
      query =
        %{
          kinds: filters[:kinds],
          from: filters[:from],
          to: filters[:to],
          before: before,
          variant_ids: filters[:variant_id] && [filters[:variant_id]],
          product_ids: filters[:product_id] && [filters[:product_id]],
          location_ids: Organizations.restrict_location_filter(context, filters[:location_ids]),
          limit: limit + 1
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      {page, rest} = context |> Shop.list_movements(query) |> Enum.split(limit)

      {:ok,
       %{
         movements: describe(context, page),
         next_cursor: if(rest != [] and page != [], do: encode_cursor(List.last(page)))
       }}
    end
  end

  defp describe(_context, []), do: []

  defp describe(context, rows) do
    variants =
      context
      |> Shop.list_variants(%{ids: rows |> Enum.map(& &1.variant_id) |> Enum.uniq()})
      |> Map.new(&{&1.id, &1})

    products =
      context
      |> Shop.list_products(%{
        ids: variants |> Map.values() |> Enum.map(& &1.product_id) |> Enum.uniq(),
        statuses: Shop.product_statuses()
      })
      |> Map.new(&{&1.id, &1})

    orders =
      case rows |> Enum.map(& &1.order_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
        [] -> %{}
        _ids -> order_numbers(context, rows)
      end

    actors =
      case rows |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) |> Enum.uniq() do
        [] -> %{}
        ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
      end

    Enum.map(rows, fn row ->
      variant = variants[row.variant_id]
      product = variant && products[variant.product_id]

      row
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.merge(%{
        product_id: variant && variant.product_id,
        product_title: product && product.title,
        variant_title: variant && variant.title,
        sku: variant && variant.sku,
        order_number: orders[row.order_id],
        actor_name: actors[row.user_id]
      })
    end)
  end

  defp order_numbers(context, rows) do
    rows
    |> Enum.map(& &1.order_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn id ->
      case Shop.get_order(context, id) do
        %{number: number} -> [{id, number}]
        nil -> []
      end
    end)
    |> Map.new()
  end

  defp encode_cursor(row),
    do: Base.url_encode64("#{DateTime.to_iso8601(row.occurred_at)}|#{row.id}", padding: false)

  defp decode_cursor(nil), do: {:ok, nil}
  defp decode_cursor(""), do: {:ok, nil}

  defp decode_cursor(cursor) do
    with {:ok, text} <- Base.url_decode64(cursor, padding: false),
         [at, id] <- String.split(text, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         {:ok, id} <- Ecto.UUID.cast(id) do
      {:ok, {at, id}}
    else
      _invalid -> {:error, :invalid_cursor}
    end
  end

  @doc "A variant's ledger, newest first."
  def ledger(context, variant_id, filters \\ %{}) do
    with %{} = variant <- Shop.get_variant(context, variant_id) || {:error, :not_found},
         {:ok, _product} <- ManageCatalog.get(context, variant.product_id) do
      rows = Shop.list_movements(context, Map.merge(filters, %{variant_ids: [variant.id]}))
      {:ok, Organizations.filter_by_location_scope(context, rows)}
    end
  end

  defp movements(context, variant, %{kind: :receive} = params) do
    one(context, variant, params, %{kind: :receive, quantity: params[:quantity]})
  end

  defp movements(context, variant, %{kind: :adjustment} = params) do
    one(context, variant, params, %{
      kind: :adjustment,
      quantity: params[:quantity],
      reason: params[:reason]
    })
  end

  defp movements(context, variant, %{kind: :recount, counted: counted} = params)
       when is_integer(counted) and counted >= 0 do
    {:ok,
     [
       base(context, variant, params)
       |> Map.merge(%{kind: :adjustment, counted: counted, reason: :recount})
     ]}
  end

  defp movements(context, variant, %{kind: :transfer} = params) do
    transfer_id = Ecto.UUID.generate()

    with {:ok, sides} <-
           Shop.transfer_movements(
             params[:quantity],
             params[:location_id],
             params[:to_location_id]
           ) do
      {:ok,
       Enum.map(sides, fn side ->
         context
         |> base(variant, params)
         |> Map.merge(side)
         |> Map.put(:transfer_id, transfer_id)
       end)}
    end
  end

  defp movements(_context, _variant, %{kind: :recount}), do: {:error, :invalid_quantity}
  defp movements(_context, _variant, _params), do: {:error, :invalid_movement}

  defp one(context, variant, params, movement) do
    movement = Map.merge(base(context, variant, params), movement)

    with :ok <- Shop.validate_movement(movement), do: {:ok, [movement]}
  end

  defp base(context, variant, params) do
    %{
      variant_id: variant.id,
      location_id: params[:location_id],
      note: params[:note],
      unit_cost_cents: params[:unit_cost_cents],
      user_id: context.user_id,
      occurred_at: params[:occurred_at] || DateTime.utc_now()
    }
  end

  defp authorize(context, movements) do
    movements
    |> Enum.map(& &1.location_id)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn location_id, :ok ->
      case Organizations.authorize_location(context, location_id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize(params) do
    params = Map.new(params, fn {key, value} -> {to_key(key), value} end)

    params
    |> Map.update(:kind, nil, &to_atom(&1, [:receive, :adjustment, :recount, :transfer]))
    |> Map.update(:reason, nil, &to_atom(&1, Shop.adjustment_reasons()))
  end

  @keys ~w(kind quantity counted reason note unit_cost_cents location_id to_location_id occurred_at)a

  defp to_key(key) when is_atom(key), do: key
  defp to_key(key) when is_binary(key), do: Enum.find(@keys, key, &(Atom.to_string(&1) == key))

  defp to_atom(value, allowed) when is_atom(value), do: if(value in allowed, do: value)

  defp to_atom(value, allowed) when is_binary(value),
    do: Enum.find(allowed, &(Atom.to_string(&1) == value))

  defp to_atom(_value, _allowed), do: nil
end
