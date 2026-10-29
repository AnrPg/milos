defmodule Palee.Fiscal.Domain.SalesTaxRateTable do
  @moduledoc """
  A US gym's own sales tax rates (ADR-244), used by the `RateTable` sales
  tax calculator until a provider (Stripe Tax, Avalara) is connected.

  A row is `%{state, zip, rate_bp, label}`: a two-letter state (or DC, PR
  and the other USPS codes), an optional five-digit ZIP code and the
  combined rate (state + county + city + district) in basis points. A ZIP
  row wins over its state's row, so a gym enters its state rate once and
  the ZIP codes whose local rate differs.

  Whether a gym membership is taxable at all differs by state (and some
  cities tax it when the state does not); the gym and its accountant decide
  which rate applies, and a package that is not taxable uses the `exempt`
  category with its reason.
  """

  @states ~w(AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE
             NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY PR GU VI AS MP)
  @max_rows 2_000
  @max_label 120

  def states, do: @states
  def max_rows, do: @max_rows

  @doc """
  `{:ok, rows}` normalised and sorted (state, then state-wide first), or
  `{:error, {:invalid_fields, %{"rates.N.field" => reason}}}`.
  """
  def normalize(rows) when is_list(rows) do
    if length(rows) > @max_rows do
      {:error, {:invalid_fields, %{rates: :too_many}}}
    else
      {normalized, errors} =
        rows
        |> Enum.with_index()
        |> Enum.reduce({[], %{}}, fn {row, index}, {acc, errors} ->
          case row(row) do
            {:ok, row} -> {[row | acc], errors}
            {:error, field, reason} -> {acc, Map.put(errors, "rates.#{index}.#{field}", reason)}
          end
        end)

      errors = duplicates(normalized, errors)

      if errors == %{},
        do: {:ok, Enum.sort_by(normalized, &{&1.state, &1.zip || ""})},
        else: {:error, {:invalid_fields, errors}}
    end
  end

  def normalize(_rows), do: {:error, {:invalid_fields, %{rates: :invalid}}}

  defp row(row) when is_map(row) do
    state = row |> value(:state) |> upcase()
    zip = row |> value(:zip) |> blank()
    rate = value(row, :rate_bp)
    label = row |> value(:label) |> blank()

    cond do
      state not in @states -> {:error, :state, :invalid}
      not (is_nil(zip) or Regex.match?(~r/^\d{5}$/, zip)) -> {:error, :zip, :invalid}
      not (is_integer(rate) and rate >= 0 and rate < 10_000) -> {:error, :rate_bp, :invalid}
      is_binary(label) and String.length(label) > @max_label -> {:error, :label, :too_long}
      true -> {:ok, %{state: state, zip: zip, rate_bp: rate, label: label}}
    end
  end

  defp row(_row), do: {:error, :row, :invalid}

  defp duplicates(rows, errors) do
    rows
    |> Enum.frequencies_by(&{&1.state, &1.zip})
    |> Enum.filter(fn {_place, count} -> count > 1 end)
    |> Enum.reduce(errors, fn {{state, zip}, _count}, errors ->
      Map.put(errors, "rates.#{state}.#{zip || "state"}", :duplicate)
    end)
  end

  @doc """
  The rate of a place: the ZIP code's row, else the state's row.
  `{:ok, rate_bp}` or `{:error, :sales_tax_rate_missing}`.
  """
  def lookup(rows, state, postal_code) do
    state = upcase(state)
    zip = postal_code |> to_string() |> String.slice(0, 5)

    case Enum.find(rows, &(&1.state == state and &1.zip == zip)) ||
           Enum.find(rows, &(&1.state == state and is_nil(&1.zip))) do
      %{rate_bp: rate} -> {:ok, rate}
      nil -> {:error, :sales_tax_rate_missing}
    end
  end

  defp value(row, key), do: Map.get(row, key, Map.get(row, Atom.to_string(key)))

  defp upcase(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase(_value), do: nil

  defp blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank(_value), do: nil
end
