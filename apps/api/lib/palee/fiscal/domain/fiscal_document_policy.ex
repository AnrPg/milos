defmodule Palee.Fiscal.Domain.FiscalDocumentPolicy do
  @moduledoc """
  Builds a fiscal document from a sale request and checks it against the
  law of the seller's country (ADR-241). Pure: the store numbers, journals
  and saves what this returns.

  A request:

      %{
        kind: "receipt" | "invoice",
        issue_date: ~D[...],            # the gym-local business date
        currency: "EUR",                # default: the country's currency
        prices_include_tax: true,       # default true (retail prices)
        buyer: %{name, tax_id, vat_number, street, building_number,
                 postal_code, city, region, country_code, email} | nil,
        payment_method: "cash" | "card" | "bank_transfer" | "online" | "other" | nil,
        lines: [%{description, quantity, unit_price_cents, discount_cents,
                  tax_category, rate_bp (US sales tax only), exemption_reason,
                  source_type, source_id}],
        source_type:, source_id:, idempotency_key:
      }

  Credit notes are built from the document they correct with
  `credit_note/4`.
  """

  alias Palee.Fiscal.Domain.{CountryProfile, TaxCalculation, VatRates}

  @kinds ~w(receipt invoice)
  @currencies ~w(EUR CHF GBP USD)
  @payment_methods ~w(cash card bank_transfer online other)
  @max_lines 200
  @max_text 300

  def kinds, do: @kinds ++ ["credit_note"]
  def payment_methods, do: @payment_methods
  def currencies, do: @currencies

  @doc """
  `{:ok, document}` with `lines` and totals, or `{:error, reason}`.
  `identity` is the seller's complete identity (atom keys).
  """
  def build(identity, request) do
    with {:ok, profile} <- CountryProfile.fetch(identity.country_code),
         :ok <- complete(profile, identity),
         {:ok, kind} <- kind(request[:kind]),
         {:ok, date} <- issue_date(request[:issue_date]),
         {:ok, currency} <- currency(request[:currency], profile),
         {:ok, payment_method} <- payment_method(request[:payment_method]),
         {:ok, buyer} <- buyer(kind, request[:buyer], profile),
         {:ok, lines} <- lines(request[:lines], identity, date),
         prices_include_tax = Map.get(request, :prices_include_tax, true) != false,
         {:ok, totals} <- TaxCalculation.compute(lines, prices_include_tax) do
      {:ok,
       %{
         kind: kind,
         issue_date: date,
         currency: currency,
         prices_include_tax: prices_include_tax,
         country_code: identity.country_code,
         language: request[:language] || identity[:document_language] || hd(profile.languages),
         seller: seller_snapshot(identity),
         buyer: buyer,
         payment_method: payment_method,
         source_type: request[:source_type],
         source_id: request[:source_id],
         idempotency_key: request[:idempotency_key],
         corrects_document_id: nil,
         net_cents: totals.net_cents,
         tax_cents: totals.tax_cents,
         gross_cents: totals.gross_cents,
         tax_breakdown: totals.groups,
         lines: number_lines(totals.lines)
       }}
    end
  end

  @doc """
  A credit note correcting `original` (with `lines`) by `requested`:
  `:all` (cancels what is left) or `[%{position, quantity}]`.
  `credited` maps an original line position to `%{quantity, amount_cents}`
  already credited by earlier credit notes. The quantities and amounts of
  all credit notes never exceed the original's.
  """
  def credit_note(original, credited, requested, %Date{} = issue_date) do
    with :ok <- creditable(original),
         {:ok, wanted} <- wanted_quantities(original.lines, credited, requested),
         {:ok, lines} <- credit_lines(original.lines, credited, wanted),
         {:ok, totals} <- TaxCalculation.compute(lines, original.prices_include_tax) do
      {:ok,
       %{
         kind: "credit_note",
         issue_date: issue_date,
         currency: original.currency,
         prices_include_tax: original.prices_include_tax,
         country_code: original.country_code,
         language: original.language,
         seller: original.seller,
         buyer: original.buyer,
         payment_method: original.payment_method,
         source_type: original.source_type,
         source_id: original.source_id,
         corrects_document_id: original.id,
         net_cents: totals.net_cents,
         tax_cents: totals.tax_cents,
         gross_cents: totals.gross_cents,
         tax_breakdown: totals.groups,
         lines: number_lines(totals.lines)
       }}
    end
  end

  # ── Checks ────────────────────────────────────────────────────────────────

  defp complete(profile, identity) do
    if CountryProfile.missing_fields(profile, identity) == [],
      do: :ok,
      else: {:error, :fiscal_identity_incomplete}
  end

  defp kind(kind) when kind in @kinds, do: {:ok, kind}
  defp kind(_kind), do: {:error, :invalid_document_kind}

  defp issue_date(%Date{} = date), do: {:ok, date}
  defp issue_date(_date), do: {:error, :invalid_issue_date}

  defp currency(nil, profile), do: {:ok, profile.currency}
  defp currency(currency, _profile) when currency in @currencies, do: {:ok, currency}
  defp currency(_currency, _profile), do: {:error, :unsupported_currency}

  defp payment_method(nil), do: {:ok, nil}
  defp payment_method(method) when method in @payment_methods, do: {:ok, method}
  defp payment_method(_method), do: {:error, :invalid_payment_method}

  defp buyer("receipt", nil, _profile), do: {:ok, nil}

  defp buyer("invoice", nil, _profile), do: {:error, :buyer_required}

  defp buyer(kind, buyer, profile) when is_map(buyer) do
    buyer =
      buyer
      |> Map.take(~w(name tax_id vat_number street building_number postal_code city region country_code email)a)
      |> Map.new(fn {key, value} -> {key, clean(value)} end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    cond do
      Enum.any?(buyer, fn {_key, value} -> String.length(value) > @max_text end) ->
        {:error, :buyer_field_too_long}

      kind == "invoice" and
          Enum.any?([:name, :street, :postal_code, :city, :country_code], &(!Map.has_key?(buyer, &1))) ->
        {:error, :buyer_address_required}

      # A Greek ΤΠΥ is reported with the buyer's ΑΦΜ.
      kind == "invoice" and profile.authority == :mydata and
          not (Map.has_key?(buyer, :vat_number) or Map.has_key?(buyer, :tax_id)) ->
        {:error, :buyer_tax_id_required}

      true ->
        {:ok, if(buyer == %{}, do: nil, else: buyer)}
    end
  end

  defp buyer(_kind, _buyer, _profile), do: {:error, :invalid_buyer}

  defp lines(lines, identity, date) when is_list(lines) and lines != [] do
    if length(lines) > @max_lines do
      {:error, :too_many_lines}
    else
      lines
      |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
        case line(line, identity, date) do
          {:ok, line} -> {:cont, {:ok, [line | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, lines} -> {:ok, Enum.reverse(lines)}
        error -> error
      end
    end
  end

  defp lines(_lines, _identity, _date), do: {:error, :no_lines}

  defp line(line, identity, date) do
    category = line[:tax_category] || "standard"
    description = clean(line[:description])

    cond do
      is_nil(description) or String.length(description) > @max_text ->
        {:error, :invalid_line_description}

      not CountryProfile.vat_registered?(identity) and category != "exempt" ->
        {:error, :business_not_vat_registered}

      category == "exempt" and is_nil(clean(line[:exemption_reason])) ->
        {:error, :exemption_reason_required}

      true ->
        with {:ok, rate} <- line_rate(identity.country_code, category, line[:rate_bp], date) do
          {:ok,
           %{
             description: description,
             quantity: line[:quantity],
             unit_price_cents: line[:unit_price_cents],
             discount_cents: line[:discount_cents] || 0,
             tax_category: category,
             rate_bp: rate,
             exemption_reason: clean(line[:exemption_reason]),
             source_type: line[:source_type],
             source_id: line[:source_id]
           }}
        end
    end
  end

  # US sales tax: the caller brings the rate from the sales tax port.
  defp line_rate("US", "sales_tax", rate, _date) when is_integer(rate) and rate >= 0 and rate < 10_000,
    do: {:ok, rate}

  defp line_rate("US", "sales_tax", _rate, _date), do: {:error, :invalid_tax_rate}

  defp line_rate(country, category, _rate, date) do
    if category in VatRates.categories(country),
      do: VatRates.rate(country, category, date),
      else: {:error, :unknown_tax_category}
  end

  defp creditable(%{kind: kind}) when kind in @kinds, do: :ok
  defp creditable(_original), do: {:error, :not_creditable}

  defp wanted_quantities(lines, credited, :all) do
    wanted =
      lines
      |> Enum.map(fn line -> {line.position, line.quantity - credited_quantity(credited, line)} end)
      |> Enum.reject(fn {_position, quantity} -> quantity <= 0 end)

    if wanted == [], do: {:error, :already_credited}, else: {:ok, wanted}
  end

  defp wanted_quantities(lines, credited, requested) when is_list(requested) and requested != [] do
    by_position = Map.new(lines, &{&1.position, &1})

    requested
    |> Enum.reduce_while({:ok, %{}}, fn item, {:ok, acc} ->
      position = item[:position]
      quantity = item[:quantity]

      case Map.get(by_position, position) do
        nil ->
          {:halt, {:error, :unknown_line}}

        _line when not (is_integer(quantity) and quantity > 0) ->
          {:halt, {:error, :invalid_quantity}}

        line ->
          total = Map.get(acc, position, 0) + quantity

          if total > line.quantity - credited_quantity(credited, line),
            do: {:halt, {:error, :credit_exceeds_document}},
            else: {:cont, {:ok, Map.put(acc, position, total)}}
      end
    end)
    |> case do
      {:ok, wanted} -> {:ok, Enum.sort(wanted)}
      error -> error
    end
  end

  defp wanted_quantities(_lines, _credited, _requested), do: {:error, :invalid_credit_request}

  defp credit_lines(lines, credited, wanted) do
    by_position = Map.new(lines, &{&1.position, &1})

    {:ok,
     Enum.map(wanted, fn {position, quantity} ->
       line = Map.fetch!(by_position, position)
       done = Map.get(credited, position, %{quantity: 0, amount_cents: 0})
       original_amount = line.quantity * line.unit_price_cents - line.discount_cents

       amount =
         if done.quantity + quantity == line.quantity,
           do: original_amount - done.amount_cents,
           else: div(original_amount * quantity, line.quantity)

       %{
         description: line.description,
         quantity: quantity,
         unit_price_cents: line.unit_price_cents,
         discount_cents: max(quantity * line.unit_price_cents - amount, 0),
         tax_category: line.tax_category,
         rate_bp: line.rate_bp,
         exemption_reason: line.exemption_reason,
         source_type: line.source_type,
         source_id: line.source_id,
         corrects_position: position
       }
     end)}
  end

  defp credited_quantity(credited, line),
    do: credited |> Map.get(line.position, %{quantity: 0}) |> Map.fetch!(:quantity)

  defp number_lines(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.map(fn {line, position} -> Map.put(line, :position, position) end)
  end

  @seller_fields ~w(legal_name trade_name country_code tax_id vat_number tax_office
                    registration_number activity_code vat_scheme street building_number
                    postal_code city region email phone branch_code)a

  @doc "The seller as printed on a document issued now."
  def seller_snapshot(identity) do
    identity
    |> Map.take(@seller_fields)
    |> Map.reject(fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(value), do: value |> to_string() |> clean()
end
