defmodule Palee.Infrastructure.Shop.EctoShopStore do
  @moduledoc """
  Ecto adapter of `Shop.Ports.ShopStore` (ADR-190).

  Stock: `apply_movements/2` is the only writer of `shop_stock_levels`. It
  ensures a level row exists for every (variant, branch) it touches, locks
  them all with `FOR UPDATE` in a fixed order (variant id, then branch, so
  two concurrent orders cannot deadlock), applies each movement with
  `StockLedger.apply_movement/2`, then writes the projection and appends the
  ledger rows. Any refused movement rolls the whole batch back, and the
  projection's check constraint backs the same invariants in the database.
  """

  @behaviour Palee.Shop.Ports.ShopStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo
  alias Palee.Shop.Domain.StockLedger

  alias Palee.Shop.{
    Order,
    OrderLine,
    Product,
    PromotionCode,
    StockLevel,
    StockMovement,
    Variant
  }

  # ── Transactions ─────────────────────────────────────────────────────────

  @impl true
  def transaction(_context, fun) when is_function(fun, 0) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
        :ok -> :ok
      end
    end)
  end

  # ── Catalog ──────────────────────────────────────────────────────────────

  @impl true
  def list_products(_context, filters) do
    Product
    |> tenant_scope()
    |> filter_products(filters)
    |> order_by([product], asc: product.position, desc: product.inserted_at)
    |> limit(^Map.get(filters, :limit, 500))
    |> Repo.all()
    |> with_variants()
  end

  defp filter_products(query, filters) do
    Enum.reduce(filters, query, fn
      {:statuses, statuses}, query when is_list(statuses) ->
        where(query, [product], product.status in ^statuses)

      {:ids, ids}, query when is_list(ids) ->
        where(query, [product], product.id in ^ids)

      {:visibility, visibility}, query when not is_nil(visibility) ->
        where(query, [product], product.visibility == ^visibility)

      {:sell_in_app, true}, query ->
        where(query, [product], product.sell_in_app == true)

      {:sell_at_desk, true}, query ->
        where(query, [product], product.sell_at_desk == true)

      {:category, category}, query when is_binary(category) and category != "" ->
        where(query, [product], product.category == ^category)

      {:q, term}, query when is_binary(term) and term != "" ->
        pattern = "%" <> String.replace(term, ~r/[\\%_]/, "\\\\\\0") <> "%"
        where(query, [product], ilike(product.title, ^pattern))

      _other, query ->
        query
    end)
  end

  @impl true
  def get_product(_context, id) do
    case Product |> tenant_scope() |> Repo.get(id) do
      nil -> nil
      product -> product |> List.wrap() |> with_variants() |> hd()
    end
  end

  @impl true
  def save_product(context, nil, attrs) do
    %Product{organization_id: context.organization_id}
    |> Product.changeset(attrs)
    |> Repo.insert()
    |> loaded_product()
  end

  def save_product(_context, id, attrs) do
    case Product |> tenant_scope() |> lock("FOR UPDATE") |> Repo.get(id) do
      nil -> {:error, :not_found}
      product -> product |> Product.changeset(attrs) |> Repo.update() |> loaded_product()
    end
  end

  defp loaded_product({:ok, product}),
    do: {:ok, product |> List.wrap() |> with_variants() |> hd()}

  defp loaded_product(error), do: error

  @impl true
  def list_variants(_context, filters) do
    Variant
    |> tenant_scope()
    |> filter_variants(filters)
    |> order_by([variant], asc: variant.position, asc: variant.inserted_at)
    |> Repo.all()
    |> with_stock()
  end

  defp filter_variants(query, filters) do
    Enum.reduce(filters, query, fn
      {:ids, ids}, query when is_list(ids) ->
        where(query, [variant], variant.id in ^ids)

      {:product_ids, ids}, query when is_list(ids) ->
        where(query, [variant], variant.product_id in ^ids)

      {:include_archived, false}, query ->
        where(query, [variant], is_nil(variant.archived_at))

      {:sku, sku}, query when is_binary(sku) ->
        where(query, [variant], variant.sku == ^sku)

      _other, query ->
        query
    end)
  end

  @impl true
  def get_variant(context, id) do
    case list_variants(context, %{ids: [id]}) do
      [variant] -> variant
      [] -> nil
    end
  end

  @impl true
  def save_variant(context, nil, attrs) do
    %Variant{organization_id: context.organization_id}
    |> Variant.changeset(attrs)
    |> Repo.insert()
    |> loaded_variant(context)
  end

  def save_variant(context, id, attrs) do
    case Variant |> tenant_scope() |> lock("FOR UPDATE") |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      variant ->
        variant
        |> Variant.changeset(Map.drop(attrs, [:product_id, "product_id"]))
        |> Repo.update()
        |> loaded_variant(context)
    end
  end

  defp loaded_variant({:ok, variant}, context), do: {:ok, get_variant(context, variant.id)}
  defp loaded_variant(error, _context), do: error

  defp with_variants([]), do: []

  defp with_variants(products) do
    ids = Enum.map(products, & &1.id)

    variants =
      Variant
      |> tenant_scope()
      |> where([variant], variant.product_id in ^ids)
      |> order_by([variant], asc: variant.position, asc: variant.inserted_at)
      |> Repo.all()
      |> with_stock()
      |> Enum.group_by(& &1.product_id)

    Enum.map(
      products,
      &(&1
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> Map.put(:variants, Map.get(variants, &1.id, [])))
    )
  end

  defp with_stock([]), do: []

  defp with_stock(variants) do
    levels =
      StockLevel
      |> tenant_scope()
      |> where([level], level.variant_id in ^Enum.map(variants, & &1.id))
      |> Repo.all()
      |> Enum.group_by(& &1.variant_id)

    Enum.map(variants, fn variant ->
      rows = Map.get(levels, variant.id, [])
      total = StockLedger.total(Enum.map(rows, &level_map/1))

      variant
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Map.put(:stock, %{
        on_hand: total.on_hand,
        reserved: total.reserved,
        available: StockLedger.available(total),
        by_location: Enum.map(rows, &level_map/1)
      })
    end)
  end

  defp level_map(%StockLevel{} = level) do
    %{
      variant_id: level.variant_id,
      location_id: level.location_id,
      on_hand: level.on_hand,
      reserved: level.reserved,
      available: level.on_hand - level.reserved
    }
  end

  # ── Stock ────────────────────────────────────────────────────────────────

  @impl true
  def apply_movements(_context, []), do: {:ok, %{movements: [], levels: []}}

  def apply_movements(context, movements) do
    Repo.transaction(fn ->
      keys =
        movements
        |> Enum.map(&{&1.variant_id, Map.get(&1, :location_id)})
        |> Enum.uniq()
        |> Enum.sort()

      locked = lock_levels(context, keys)

      {levels, rows} =
        Enum.reduce(movements, {locked, []}, fn movement, {levels, rows} ->
          key = {movement.variant_id, Map.get(movement, :location_id)}
          %StockLevel{} = level = Map.fetch!(levels, key)
          current = %{on_hand: level.on_hand, reserved: level.reserved}

          case counted(current, movement) do
            :unchanged ->
              {levels, rows}

            {:error, reason} ->
              Repo.rollback(
                {reason,
                 %{variant_id: movement.variant_id, location_id: Map.get(movement, :location_id)}}
              )

            {:ok, movement} ->
              apply_one(levels, rows, key, level, current, movement)
          end
        end)

      now = DateTime.utc_now()

      Enum.each(keys, fn key ->
        level = Map.fetch!(levels, key)

        StockLevel
        |> where([row], row.id == ^level.id)
        |> Repo.update_all(
          set: [on_hand: level.on_hand, reserved: level.reserved, updated_at: now]
        )
      end)

      saved =
        rows
        |> Enum.reverse()
        |> Enum.map(fn movement ->
          movement
          |> Map.put_new(:occurred_at, now)
          |> StockMovement.changeset()
          |> Repo.insert()
          |> case do
            {:ok, row} -> row
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      %{movements: saved, levels: Enum.map(keys, &level_map(Map.fetch!(levels, &1)))}
    end)
    |> case do
      {:error, {reason, at}} when is_atom(reason) -> {:error, {reason, at}}
      other -> other
    end
  end

  defp apply_one(levels, rows, key, level, current, movement) do
    case StockLedger.apply_movement(current, movement) do
      {:ok, next} ->
        {Map.put(levels, key, %{level | on_hand: next.on_hand, reserved: next.reserved}),
         [movement | rows]}

      {:error, reason} ->
        Repo.rollback(
          {reason,
           %{variant_id: movement.variant_id, location_id: Map.get(movement, :location_id)}}
        )
    end
  end

  # A recount names the counted stock; the adjustment is computed here, on
  # the locked level, so a concurrent sale cannot make it wrong.
  defp counted(current, %{counted: counted} = movement) do
    case StockLedger.recount(current, counted) do
      {:ok, nil} ->
        :unchanged

      {:ok, delta} ->
        {:ok,
         movement
         |> Map.delete(:counted)
         |> Map.merge(%{
           kind: :adjustment,
           quantity: delta,
           reason: Map.get(movement, :reason) || :recount
         })}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp counted(_current, movement), do: {:ok, movement}

  defp lock_levels(context, keys) do
    now = DateTime.utc_now()

    rows =
      Enum.map(keys, fn {variant_id, location_id} ->
        %{
          id: Ecto.UUID.generate(),
          organization_id: context.organization_id,
          variant_id: variant_id,
          location_id: location_id,
          on_hand: 0,
          reserved: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(StockLevel, rows, on_conflict: :nothing)

    Enum.reduce(keys, %{}, fn {variant_id, location_id} = key, acc ->
      query =
        StockLevel
        |> tenant_scope()
        |> where([level], level.variant_id == ^variant_id)
        |> location_is(location_id)
        |> lock("FOR UPDATE")

      case Repo.one(query) do
        nil -> Repo.rollback(:variant_not_found)
        level -> Map.put(acc, key, level)
      end
    end)
  end

  defp location_is(query, nil), do: where(query, [level], is_nil(level.location_id))
  defp location_is(query, id), do: where(query, [level], level.location_id == ^id)

  @impl true
  def stock_levels(_context, variant_ids) do
    StockLevel
    |> tenant_scope()
    |> where([level], level.variant_id in ^variant_ids)
    |> Repo.all()
    |> Enum.map(&level_map/1)
  end

  @impl true
  def list_movements(_context, filters) do
    StockMovement
    |> tenant_scope()
    |> filter_movements(filters)
    |> order_by([movement], desc: movement.occurred_at, desc: movement.inserted_at)
    |> limit(^Map.get(filters, :limit, 500))
    |> Repo.all()
  end

  defp filter_movements(query, filters) do
    Enum.reduce(filters, query, fn
      {:variant_ids, ids}, query when is_list(ids) -> where(query, [m], m.variant_id in ^ids)
      {:kinds, kinds}, query when is_list(kinds) -> where(query, [m], m.kind in ^kinds)
      {:order_id, id}, query when is_binary(id) -> where(query, [m], m.order_id == ^id)
      {:from, %DateTime{} = at}, query -> where(query, [m], m.occurred_at >= ^at)
      {:location_ids, ids}, query when is_list(ids) -> where(query, [m], m.location_id in ^ids)
      _other, query -> query
    end)
  end

  # ── Orders ───────────────────────────────────────────────────────────────

  # One counter per business, taken under a transaction-scoped advisory lock
  # so concurrent orders never share a number.
  @impl true
  def next_order_number(context) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      "shop_order_number:" <> context.organization_id
    ])

    Order
    |> tenant_scope()
    |> select([order], coalesce(max(order.number), 0))
    |> Repo.one()
    |> Kernel.+(1)
  end

  @impl true
  def get_order_by_key(_context, key) when is_binary(key) do
    case Order |> tenant_scope() |> Repo.get_by(idempotency_key: key) do
      nil -> nil
      order -> Repo.preload(order, lines: from(line in OrderLine, order_by: line.inserted_at))
    end
  end

  @impl true
  def insert_order(context, attrs, lines) do
    Repo.transaction(fn ->
      number = next_order_number(context)

      order =
        attrs
        |> Map.put(:number, number)
        |> Order.create_changeset()
        |> Ecto.Changeset.put_change(:organization_id, context.organization_id)
        |> Repo.insert()
        |> case do
          {:ok, order} -> order
          {:error, changeset} -> Repo.rollback(changeset)
        end

      saved =
        Enum.map(lines, fn line ->
          line
          |> Map.put(:order_id, order.id)
          |> OrderLine.create_changeset()
          |> Ecto.Changeset.put_change(:organization_id, context.organization_id)
          |> Repo.insert()
          |> case do
            {:ok, line} -> line
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      %{order | lines: saved}
    end)
  end

  @impl true
  def get_order(_context, id, opts) do
    query = Order |> tenant_scope() |> where([order], order.id == ^id)
    query = if Keyword.get(opts, :lock), do: lock(query, "FOR UPDATE"), else: query

    case Repo.one(query) do
      nil -> nil
      order -> Repo.preload(order, lines: from(line in OrderLine, order_by: line.inserted_at))
    end
  end

  @impl true
  def update_order(context, id, attrs) do
    case Order |> tenant_scope() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      order ->
        with {:ok, _order} <- order |> Order.update_changeset(attrs) |> Repo.update() do
          {:ok, get_order(context, id, [])}
        end
    end
  end

  @impl true
  def update_order_line(_context, id, attrs) do
    case OrderLine |> tenant_scope() |> Repo.get(id) do
      nil -> {:error, :not_found}
      line -> line |> OrderLine.update_changeset(attrs) |> Repo.update()
    end
  end

  @impl true
  def list_orders(_context, filters) do
    Order
    |> tenant_scope()
    |> filter_orders(filters)
    |> order_by([order], desc: order.placed_at)
    |> limit(^Map.get(filters, :limit, 200))
    |> Repo.all()
    |> Repo.preload(lines: from(line in OrderLine, order_by: line.inserted_at))
  end

  defp filter_orders(query, filters) do
    Enum.reduce(filters, query, fn
      {:user_id, id}, query when is_binary(id) ->
        where(query, [order], order.user_id == ^id)

      {:statuses, statuses}, query when is_list(statuses) ->
        where(query, [order], order.status in ^statuses)

      {:payment_statuses, statuses}, query when is_list(statuses) ->
        where(query, [order], order.payment_status in ^statuses)

      {:channel, channel}, query when not is_nil(channel) ->
        where(query, [order], order.channel == ^channel)

      # ADR-186: branch-scoped staff see orders picked up at their branches;
      # an order with no pickup branch is for all-scoped staff only.
      {:location_ids, ids}, query when is_list(ids) ->
        where(query, [order], order.pickup_location_id in ^ids)

      {:expired_before, %DateTime{} = at}, query ->
        where(query, [order], not is_nil(order.expires_at) and order.expires_at <= ^at)

      {:from, %DateTime{} = at}, query ->
        where(query, [order], order.placed_at >= ^at)

      {:number, number}, query when is_integer(number) ->
        where(query, [order], order.number == ^number)

      _other, query ->
        query
    end)
  end

  @impl true
  def units_held(_context, user_id, product_ids) do
    from(line in OrderLine,
      join: order in Order,
      on: order.id == line.order_id,
      where: order.user_id == ^user_id and order.status != :cancelled,
      where: line.product_id in ^product_ids,
      group_by: line.product_id,
      select: {line.product_id, sum(line.quantity - line.refunded_quantity)}
    )
    |> tenant_scope_join()
    |> Repo.all()
    |> Map.new(fn {id, units} -> {id, to_integer(units)} end)
  end

  # ── Promotion codes ──────────────────────────────────────────────────────

  @impl true
  def get_promotion_code(_context, value, opts) do
    by = Keyword.get(opts, :by, :code)

    query =
      case by do
        :id -> PromotionCode |> tenant_scope() |> where([code], code.id == ^value)
        :code -> PromotionCode |> tenant_scope() |> where([code], code.code == ^value)
      end

    query = if Keyword.get(opts, :lock), do: lock(query, "FOR UPDATE"), else: query

    case cast_lookup(by, value) && Repo.one(query) do
      %PromotionCode{} = code -> code |> List.wrap() |> with_redemptions() |> hd()
      _missing -> nil
    end
  end

  defp cast_lookup(:id, value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp cast_lookup(:code, value), do: is_binary(value)

  @impl true
  def list_promotion_codes(_context, filters) do
    PromotionCode
    |> tenant_scope()
    |> filter_by(:product_id, filters[:product_id])
    |> filter_by(:post_id, filters[:post_id])
    |> then(fn query ->
      case filters[:ids] do
        ids when is_list(ids) -> where(query, [code], code.id in ^ids)
        _all -> query
      end
    end)
    |> order_by([code], desc: code.inserted_at)
    |> limit(^min(filters[:limit] || 200, 500))
    |> Repo.all()
    |> with_redemptions()
  end

  defp filter_by(query, _field, nil), do: query
  defp filter_by(query, field, value), do: where(query, [row], field(row, ^field) == ^value)

  @impl true
  def save_promotion_code(context, nil, attrs) do
    attrs
    |> PromotionCode.create_changeset()
    |> Ecto.Changeset.put_change(:organization_id, context.organization_id)
    |> Repo.insert()
    |> loaded_code()
  end

  def save_promotion_code(_context, id, attrs) do
    case PromotionCode |> tenant_scope() |> lock("FOR UPDATE") |> Repo.get(id) do
      nil -> {:error, :not_found}
      code -> code |> PromotionCode.update_changeset(attrs) |> Repo.update() |> loaded_code()
    end
  end

  defp loaded_code({:ok, code}), do: {:ok, code |> List.wrap() |> with_redemptions() |> hd()}
  defp loaded_code(error), do: error

  defp with_redemptions([]), do: []

  defp with_redemptions(codes) do
    ids = Enum.map(codes, & &1.id)

    counts =
      from(order in Order,
        where: order.promotion_code_id in ^ids and order.status != :cancelled,
        group_by: order.promotion_code_id,
        select: {order.promotion_code_id, count(order.id)}
      )
      |> tenant_scope_join()
      |> Repo.all()
      |> Map.new()

    Enum.map(codes, &%{&1 | redemptions: Map.get(counts, &1.id, 0)})
  end

  defp tenant_scope_join(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        where(query, [line], line.organization_id == ^organization_id)

      _missing ->
        where(query, false)
    end
  end

  defp tenant_scope(queryable) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) and organization_id != "" ->
        from(row in queryable, where: field(row, :organization_id) == ^organization_id)

      _missing ->
        from(row in queryable, where: false)
    end
  end

  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = value), do: Decimal.to_integer(value)
  defp to_integer(value) when is_integer(value), do: value
end
