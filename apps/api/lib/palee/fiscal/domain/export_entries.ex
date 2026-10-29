defmodule Palee.Fiscal.Domain.ExportEntries do
  @moduledoc """
  The neutral bookkeeping view every accounting export format renders
  (ADR-245). Pure: it gets fiscal documents with their lines and Finance
  payments (ADR-126 `payments` dataset rows) and returns

      %{documents: [document_entry], payments: [payment_entry]}

  A `document_entry` is

      %{id, number, kind, issue_date, currency, country_code, sign,
        prices_include_tax, payment_method, corrects_number,
        buyer: %{name, tax_id, vat_number, email, street, postal_code, city,
                 country_code},
        net_cents, tax_cents, gross_cents,            # signed
        groups: [%{tax_category, rate_bp, exemption_reason,
                   net_cents, tax_cents, gross_cents}],  # signed, per rate
        lines: [%{position, description, quantity, unit_price_cents,
                  discount_cents, amount_cents, tax_category, rate_bp,
                  exemption_reason, net_cents, tax_cents, gross_cents}]}

  Credit notes are stored with positive amounts (ADR-241); here `sign` is
  -1 and every amount of the entry, its groups and its lines is negated, so
  that a sum over entries is the period's turnover. `unit_price_cents` and
  `quantity` keep their stored (positive) values; formats that need a
  signed unit price use `sign`.

  A `payment_entry` is `%{id, paid_on, invoice_number, payment_method,
  currency, amount_cents, reference}` with `amount_cents` the amount net of
  reversals; payments reversed in full are left out.
  """

  @doc """
  Builds the entries. `lines_by_document` maps a document id to its lines;
  `numbers` maps the ids of corrected documents outside the period to
  their numbers.
  """
  def build(documents, lines_by_document, payments \\ [], numbers \\ %{}) do
    numbers = Map.merge(numbers, Map.new(documents, &{field(&1, :id), field(&1, :number)}))

    %{
      documents:
        Enum.map(
          documents,
          &document(&1, Map.get(lines_by_document, field(&1, :id), []), numbers)
        ),
      payments: payments |> Enum.map(&payment/1) |> Enum.reject(&(&1.amount_cents == 0))
    }
  end

  @doc "A tax rate as a percentage string with up to two decimals (`1900` → `\"19\"`, `550` → `\"5.5\"`)."
  def percent(rate_bp) when is_integer(rate_bp) do
    whole = div(rate_bp, 100)

    case rem(rate_bp, 100) do
      0 -> Integer.to_string(whole)
      fraction when rem(fraction, 10) == 0 -> "#{whole}.#{div(fraction, 10)}"
      fraction -> "#{whole}.#{String.pad_leading(Integer.to_string(fraction), 2, "0")}"
    end
  end

  def percent(_rate_bp), do: "0"

  defp document(document, lines, numbers) do
    sign = if field(document, :kind) == "credit_note", do: -1, else: 1
    corrects = field(document, :corrects_document_id)

    %{
      id: field(document, :id),
      number: field(document, :number),
      kind: field(document, :kind),
      issue_date: field(document, :issue_date),
      currency: field(document, :currency),
      country_code: field(document, :country_code),
      sign: sign,
      prices_include_tax: field(document, :prices_include_tax) != false,
      payment_method: field(document, :payment_method),
      corrects_number: corrects && Map.get(numbers, corrects),
      buyer: buyer(field(document, :buyer)),
      net_cents: sign * (field(document, :net_cents) || 0),
      tax_cents: sign * (field(document, :tax_cents) || 0),
      gross_cents: sign * (field(document, :gross_cents) || 0),
      groups: groups(document, lines, sign),
      lines: lines |> Enum.sort_by(&field(&1, :position)) |> Enum.map(&line(&1, sign))
    }
  end

  # The stored breakdown is authoritative; the exemption reason of a group
  # comes from its first line.
  defp groups(document, lines, sign) do
    reasons =
      Enum.reduce(lines, %{}, fn line, acc ->
        Map.put_new(
          acc,
          {field(line, :tax_category), field(line, :rate_bp)},
          field(line, :exemption_reason)
        )
      end)

    document
    |> field(:tax_breakdown)
    |> List.wrap()
    |> Enum.map(fn group ->
      key = {field(group, :tax_category), field(group, :rate_bp)}

      %{
        tax_category: elem(key, 0),
        rate_bp: elem(key, 1) || 0,
        exemption_reason: Map.get(reasons, key),
        net_cents: sign * (field(group, :net_cents) || 0),
        tax_cents: sign * (field(group, :tax_cents) || 0),
        gross_cents: sign * (field(group, :gross_cents) || 0)
      }
    end)
  end

  defp line(line, sign) do
    %{
      position: field(line, :position),
      description: field(line, :description),
      quantity: field(line, :quantity),
      unit_price_cents: field(line, :unit_price_cents),
      discount_cents: field(line, :discount_cents) || 0,
      amount_cents: sign * (field(line, :amount_cents) || 0),
      tax_category: field(line, :tax_category),
      rate_bp: field(line, :rate_bp) || 0,
      exemption_reason: field(line, :exemption_reason),
      net_cents: sign * (field(line, :net_cents) || 0),
      tax_cents: sign * (field(line, :tax_cents) || 0),
      gross_cents: sign * (field(line, :gross_cents) || 0)
    }
  end

  defp buyer(nil), do: %{}

  defp buyer(buyer) when is_map(buyer) do
    ~w(name tax_id vat_number email street building_number postal_code city country_code)a
    |> Map.new(&{&1, field(buyer, &1)})
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp payment(row) do
    %{
      id: field(row, :payment_id),
      paid_on: date(field(row, :paid_on)),
      invoice_number: field(row, :invoice_number),
      payment_method: field(row, :payment_method),
      currency: field(row, :currency),
      amount_cents: field(row, :net_amount_cents) || field(row, :amount_cents) || 0,
      reference: field(row, :invoice_number) || short_id(field(row, :payment_id))
    }
  end

  defp short_id(nil), do: nil
  defp short_id(id), do: id |> to_string() |> String.slice(0, 8)

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp date(_value), do: nil

  # Documents read back from the database carry string-keyed jsonb maps.
  defp field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
