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
  alias Palee.{Organizations, Shop}

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
