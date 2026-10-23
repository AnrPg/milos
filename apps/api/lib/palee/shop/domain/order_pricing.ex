defmodule Palee.Shop.Domain.OrderPricing do
  @moduledoc """
  Turns a cart (`[%{variant_id, quantity}]`) into priced order lines
  (ADR-190), pure. Prices come from the catalog, never from the client.

    * Repeated variants merge into one line; quantities are 1..99 per line.
    * Every variant must be live, of a product sellable through the channel
      (`ProductPolicy.sellable?/2`) and in the order's currency.
    * The member package discount (ADR-097 `member_discount_percent`)
      applies to lines of products with `member_discount_applies`.
    * A product's `per_person_limit` caps what one buyer holds across open
      and paid orders (`already` counts them per product).
    * A product-scoped promotion code (`:promotion`, see `PromotionPolicy`)
      discounts its product's lines; it never stacks with the member
      discount (each line takes the larger), and a cart without its product
      refuses it.
  """

  alias Palee.Shop.Domain.{ProductPolicy, PromotionPolicy}

  @max_quantity 99
  @max_lines 50

  @type cart_item :: %{variant_id: String.t(), quantity: pos_integer()}

  @doc """
  `{:ok, %{lines, subtotal_cents, discount_cents, total_cents, currency}}`
  or an error. `catalog` maps variant ids to `%{variant, product}`.
  `opts`: `:channel`, `:member_discount_percent`, `:already` (product id =>
  units the buyer already holds), `:promotion` (a redeemable promotion code).
  The result's `promotion_code_id` names the code when it applied.
  """
  @spec price([map()], %{optional(String.t()) => map()}, keyword() | map()) ::
          {:ok, map()} | {:error, atom()}
  def price(items, catalog, opts) do
    opts = Map.new(opts)
    channel = Map.fetch!(opts, :channel)

    with {:ok, merged} <- merge(items),
         {:ok, lines} <- build_lines(merged, catalog, channel, opts),
         {:ok, currency} <- single_currency(lines),
         :ok <- within_limits(lines, catalog, Map.get(opts, :already, %{})),
         {:ok, lines, promotion_id} <- apply_promotion(lines, Map.get(opts, :promotion)) do
      subtotal = Enum.sum(Enum.map(lines, &(&1.unit_price_cents * &1.quantity)))
      discount = Enum.sum(Enum.map(lines, & &1.discount_cents))

      {:ok,
       %{
         lines: lines,
         currency: currency,
         subtotal_cents: subtotal,
         discount_cents: discount,
         total_cents: subtotal - discount,
         promotion_code_id: promotion_id
       }}
    end
  end

  defp apply_promotion(lines, nil), do: {:ok, lines, nil}

  defp apply_promotion(lines, %{product_id: product_id} = code) do
    if Enum.any?(lines, &(&1.product_id == product_id)) do
      lines =
        Enum.map(lines, fn
          %{product_id: ^product_id} = line ->
            promo = PromotionPolicy.line_discount(code, line.unit_price_cents, line.quantity)
            discount = max(promo, line.discount_cents)

            %{
              line
              | discount_cents: discount,
                total_cents: line.unit_price_cents * line.quantity - discount
            }

          line ->
            line
        end)

      {:ok, lines, code.id}
    else
      {:error, :promotion_code_not_applicable}
    end
  end

  defp merge(items) when is_list(items) and items != [] and length(items) <= @max_lines do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      variant_id = Map.get(item, :variant_id, Map.get(item, "variant_id"))
      quantity = Map.get(item, :quantity, Map.get(item, "quantity"))

      cond do
        not is_binary(variant_id) -> {:halt, {:error, :invalid_cart}}
        not is_integer(quantity) or quantity < 1 -> {:halt, {:error, :invalid_quantity}}
        true -> {:cont, {:ok, [{variant_id, quantity} | acc]}}
      end
    end)
    |> case do
      {:ok, pairs} ->
        merged =
          pairs
          |> Enum.reverse()
          |> Enum.reduce([], fn {id, q}, acc ->
            case List.keyfind(acc, id, 0) do
              nil -> acc ++ [{id, q}]
              {^id, existing} -> List.keyreplace(acc, id, 0, {id, existing + q})
            end
          end)

        if Enum.all?(merged, fn {_id, q} -> q <= @max_quantity end),
          do: {:ok, merged},
          else: {:error, :invalid_quantity}

      error ->
        error
    end
  end

  defp merge(_items), do: {:error, :invalid_cart}

  defp build_lines(merged, catalog, channel, opts) do
    percent = Map.get(opts, :member_discount_percent)

    Enum.reduce_while(merged, {:ok, []}, fn {variant_id, quantity}, {:ok, acc} ->
      case Map.get(catalog, variant_id) do
        %{variant: %{archived_at: nil} = variant, product: product} ->
          if ProductPolicy.sellable?(product, channel) do
            {:cont, {:ok, [line(variant, product, quantity, percent) | acc]}}
          else
            {:halt, {:error, :product_not_available}}
          end

        _missing ->
          {:halt, {:error, :variant_not_found}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp line(variant, product, quantity, percent) do
    gross = variant.price_cents * quantity
    discount = discount_cents(gross, product, percent)

    %{
      variant_id: variant.id,
      product_id: product.id,
      product_title: product.title,
      variant_title: variant.title,
      sku: variant.sku,
      quantity: quantity,
      unit_price_cents: variant.price_cents,
      cost_price_cents: variant.cost_price_cents,
      tax_class: variant.tax_class,
      currency: variant.currency,
      discount_cents: discount,
      total_cents: gross - discount
    }
  end

  @doc "The member discount on a line's gross amount (rounded half up, never above it)."
  @spec discount_cents(non_neg_integer(), map(), integer() | nil) :: non_neg_integer()
  def discount_cents(gross, %{member_discount_applies: true}, percent)
      when is_integer(percent) and percent > 0 and percent <= 100,
      do: min(gross, div(gross * percent + 50, 100))

  def discount_cents(_gross, _product, _percent), do: 0

  defp single_currency(lines) do
    case lines |> Enum.map(& &1.currency) |> Enum.uniq() do
      [currency] -> {:ok, currency}
      _many -> {:error, :currency_mismatch}
    end
  end

  defp within_limits(lines, catalog, already) do
    lines
    |> Enum.group_by(& &1.product_id, & &1.quantity)
    |> Enum.reduce_while(:ok, fn {product_id, quantities}, :ok ->
      limit =
        catalog
        |> Map.values()
        |> Enum.find_value(fn %{product: product} ->
          product.id == product_id && product.per_person_limit
        end)

      held = Map.get(already, product_id, 0)

      if is_integer(limit) and held + Enum.sum(quantities) > limit,
        do: {:halt, {:error, :per_person_limit_exceeded}},
        else: {:cont, :ok}
    end)
  end
end
