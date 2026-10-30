defmodule Palee.Fiscal.Domain.TaxCalculation do
  @moduledoc """
  Line and document amounts of a fiscal document (ADR-241).

  Tax is computed **per rate group** and rounded half up (away from zero),
  as EN 16931 and myDATA expect:

    * prices without tax: `tax = round(net × rate)`;
    * prices with tax: `tax = round(gross × rate / (1 + rate))`,
      `net = gross − tax`.

  The group's net and tax are then shared out over its lines in proportion
  to each line's amount, by largest remainder, so lines, groups and the
  document always add up to the cent.

  Input lines: `%{quantity, unit_price_cents, discount_cents, rate_bp,
  tax_category}` (quantity a positive integer, amounts non-negative integer
  minor units). Output lines gain `amount_cents` (after discount, in the
  price mode), `net_cents`, `tax_cents` and `gross_cents`.
  """

  @scale 10_000

  @doc """
  `{:ok, %{lines, groups, net_cents, tax_cents, gross_cents}}` or
  `{:error, reason}`. `prices_include_tax` applies to every line.
  """
  def compute(lines, prices_include_tax) when is_list(lines) and lines != [] do
    with {:ok, lines} <- amounts(lines) do
      groups =
        lines
        |> Enum.with_index()
        |> Enum.group_by(fn {line, _index} -> {line.tax_category, line.rate_bp} end)
        |> Enum.sort_by(fn {{category, rate}, _} -> {-rate, category} end)

      {lines_by_index, group_totals} =
        Enum.reduce(groups, {%{}, []}, fn {{category, rate}, members}, {acc, totals} ->
          base = members |> Enum.map(fn {line, _} -> line.amount_cents end) |> Enum.sum()
          {net, tax} = group_split(base, rate, prices_include_tax)
          weights = Enum.map(members, fn {line, _} -> line.amount_cents end)
          nets = allocate(net, weights)
          taxes = allocate(tax, weights)

          acc =
            members
            |> Enum.zip(Enum.zip(nets, taxes))
            |> Enum.reduce(acc, fn {{line, index}, {line_net, line_tax}}, acc ->
              Map.put(acc, index, %{
                line
                | net_cents: line_net,
                  tax_cents: line_tax,
                  gross_cents: line_net + line_tax
              })
            end)

          total = %{
            tax_category: category,
            rate_bp: rate,
            net_cents: net,
            tax_cents: tax,
            gross_cents: net + tax
          }

          {acc, [total | totals]}
        end)

      lines = lines_by_index |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
      groups = Enum.reverse(group_totals)

      {:ok,
       %{
         lines: lines,
         groups: groups,
         net_cents: sum(groups, :net_cents),
         tax_cents: sum(groups, :tax_cents),
         gross_cents: sum(groups, :gross_cents)
       }}
    end
  end

  def compute(_lines, _prices_include_tax), do: {:error, :no_lines}

  defp amounts(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      quantity = line[:quantity]
      unit = line[:unit_price_cents]
      discount = line[:discount_cents] || 0
      rate = line[:rate_bp]

      cond do
        not (is_integer(quantity) and quantity > 0) ->
          {:halt, {:error, :invalid_quantity}}

        not (is_integer(unit) and unit >= 0 and is_integer(discount) and discount >= 0) ->
          {:halt, {:error, :invalid_amount}}

        discount > quantity * unit ->
          {:halt, {:error, :discount_exceeds_amount}}

        not (is_integer(rate) and rate >= 0 and rate < @scale) ->
          {:halt, {:error, :invalid_tax_rate}}

        true ->
          line =
            Map.merge(line, %{
              discount_cents: discount,
              amount_cents: quantity * unit - discount,
              net_cents: 0,
              tax_cents: 0,
              gross_cents: 0
            })

          {:cont, {:ok, [line | acc]}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  @doc "`{net, tax}` of a rate group whose lines add up to `base`."
  def group_split(base, rate_bp, true = _prices_include_tax) do
    tax = round_half_up(base * rate_bp, @scale + rate_bp)
    {base - tax, tax}
  end

  def group_split(base, rate_bp, false) do
    {base, round_half_up(base * rate_bp, @scale)}
  end

  @doc "`numerator / denominator` rounded half up, for non-negative integers."
  def round_half_up(numerator, denominator)
      when is_integer(numerator) and numerator >= 0 and is_integer(denominator) and
             denominator > 0,
      do: div(2 * numerator + denominator, 2 * denominator)

  @doc """
  Splits `total` over `weights` in proportion, by largest remainder: the
  parts are integers that add up to `total` exactly. Ties go to the earlier
  weight. All-zero weights put everything on the first part.
  """
  def allocate(total, weights) do
    weight_sum = Enum.sum(weights)

    if weight_sum == 0 do
      [total | List.duplicate(0, length(weights) - 1)]
    else
      shares =
        weights
        |> Enum.with_index()
        |> Enum.map(fn {weight, index} ->
          exact = total * weight
          {div(exact, weight_sum), rem(exact, weight_sum), index}
        end)

      leftover = total - (shares |> Enum.map(&elem(&1, 0)) |> Enum.sum())

      bumped =
        shares
        |> Enum.sort_by(fn {_floor, remainder, index} -> {-remainder, index} end)
        |> Enum.take(leftover)
        |> MapSet.new(&elem(&1, 2))

      Enum.map(shares, fn {floor, _remainder, index} ->
        if MapSet.member?(bumped, index), do: floor + 1, else: floor
      end)
    end
  end

  defp sum(rows, key), do: rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.sum()
end
