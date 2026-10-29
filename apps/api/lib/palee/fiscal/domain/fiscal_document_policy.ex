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
        buyer: %{name, tax_id, vat_number, street, building_number, peppol_id, reference,
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

  alias Palee.Fiscal.Domain.{CountryProfile, PeppolId, TaxCalculation, VatRates}

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
  `:all` (cancels what is left), `[%{position, quantity}]`, or
  `%{amount_cents: n}` (a part refund, split over what is left of each
  line in proportion, ADR-262).
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
      |> Map.take(
        ~w(name tax_id vat_number street building_number postal_code city region country_code email
           peppol_id reference)a
      )
      |> Map.new(fn {key, value} -> {key, clean(value)} end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.update(:peppol_id, nil, fn id ->
        case PeppolId.parse(id) do
          {:ok, parsed} -> PeppolId.format(parsed)
          _invalid -> id
        end
      end)
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    cond do
      # ADR-250: the buyer's Peppol address, normalised ("0208:0123456789").
      Map.has_key?(buyer, :peppol_id) and
          match?({:error, _}, PeppolId.parse(buyer.peppol_id)) ->
        {:error, :invalid_peppol_id}

      Enum.any?(buyer, fn {_key, value} -> String.length(value) > @max_text end) ->
        {:error, :buyer_field_too_long}

      kind == "invoice" and
          Enum.any?(
            [:name, :street, :postal_code, :city, :country_code],
            &(!Map.has_key?(buyer, &1))
          ) ->
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
  defp line_rate("US", "sales_tax", rate, _date)
       when is_integer(rate) and rate >= 0 and rate < 10_000,
       do: {:ok, rate}

  defp line_rate("US", "sales_tax", _rate, _date), do: {:error, :invalid_tax_rate}

  defp line_rate(country, category, _rate, date) do
    if category in VatRates.categories(country),
      do: VatRates.rate(country, category, date),
      else: {:error, :unknown_tax_category}
  end

  defp creditable(%{kind: kind}) when kind in @kinds, do: :ok
  defp creditable(_original), do: {:error, :not_creditable}

  # Each wanted credit is `{position, quantity, amount_cents}`. What is
  # left of a line is its amount minus what earlier credit notes took, so
  # credits by quantity and by amount (ADR-262) can follow one another.
  defp wanted_quantities(lines, credited, :all) do
    wanted =
      lines
      |> Enum.map(fn line ->
        {line.position, open_quantity(credited, line), remaining_amount(credited, line)}
      end)
      |> Enum.reject(fn {_position, _quantity, amount} -> amount <= 0 end)

    if wanted == [], do: {:error, :already_credited}, else: {:ok, wanted}
  end

  defp wanted_quantities(lines, credited, %{amount_cents: amount}) do
    open =
      lines
      |> Enum.map(&{&1, remaining_amount(credited, &1)})
      |> Enum.reject(fn {_line, left} -> left <= 0 end)

    total = Enum.sum(Enum.map(open, &elem(&1, 1)))

    cond do
      not (is_integer(amount) and amount > 0) -> {:error, :invalid_credit_amount}
      total == 0 -> {:error, :already_credited}
      amount > total -> {:error, :credit_exceeds_document}
      amount == total -> wanted_quantities(lines, credited, :all)
      true -> {:ok, amount_shares(open, amount, total, credited)}
    end
  end

  defp wanted_quantities(lines, credited, requested)
       when is_list(requested) and requested != [] do
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
      {:ok, wanted} -> by_quantity(wanted, by_position, credited)
      error -> error
    end
  end

  defp wanted_quantities(_lines, _credited, _requested), do: {:error, :invalid_credit_request}

  defp by_quantity(wanted, by_position, credited) do
    wanted
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn {position, quantity}, {:ok, acc} ->
      line = Map.fetch!(by_position, position)
      done = credited_quantity(credited, line)
      left = remaining_amount(credited, line)

      amount =
        if done + quantity == line.quantity,
          do: left,
          else: div(line_amount(line) * quantity, line.quantity)

      if amount > left or amount <= 0,
        do: {:halt, {:error, :credit_exceeds_document}},
        else: {:cont, {:ok, [{position, quantity, amount} | acc]}}
    end)
    |> case do
      {:ok, wanted} -> {:ok, Enum.reverse(wanted)}
      error -> error
    end
  end

  # Part of what is left, in proportion per line, rounded by largest
  # remainder so the shares add up to the cent.
  defp amount_shares(open, amount, total, credited) do
    shares =
      Enum.map(open, fn {line, left} ->
        exact = amount * left
        {line, left, div(exact, total), rem(exact, total)}
      end)

    extra = amount - Enum.sum(Enum.map(shares, &elem(&1, 2)))

    bonus =
      shares
      |> Enum.with_index()
      |> Enum.sort_by(fn {{_line, _left, _base, remainder}, index} -> {-remainder, index} end)
      |> Enum.take(extra)
      |> MapSet.new(fn {_share, index} -> index end)

    shares
    |> Enum.with_index()
    |> Enum.map(fn {{line, left, base, _remainder}, index} ->
      share = base + if(MapSet.member?(bonus, index), do: 1, else: 0)
      quantity = if share == left, do: open_quantity(credited, line), else: 1
      {line.position, quantity, share}
    end)
    |> Enum.reject(fn {_position, _quantity, share} -> share == 0 end)
  end

  defp credit_lines(lines, _credited, wanted) do
    by_position = Map.new(lines, &{&1.position, &1})

    {:ok,
     Enum.map(wanted, fn {position, quantity, amount} ->
       line = Map.fetch!(by_position, position)

       # A credit smaller than one unit's price keeps the unit price and
       # shows the rest as discount; a larger one is a single line.
       {quantity, unit_price} =
         if quantity * line.unit_price_cents >= amount,
           do: {quantity, line.unit_price_cents},
           else: {1, amount}

       %{
         description: line.description,
         quantity: quantity,
         unit_price_cents: unit_price,
         discount_cents: quantity * unit_price - amount,
         tax_category: line.tax_category,
         rate_bp: line.rate_bp,
         exemption_reason: line.exemption_reason,
         source_type: line.source_type,
         source_id: line.source_id,
         corrects_position: position
       }
     end)}
  end

  defp line_amount(line), do: line.quantity * line.unit_price_cents - line.discount_cents

  defp remaining_amount(credited, line) do
    done = Map.get(credited, line.position, %{amount_cents: 0})
    line_amount(line) - done.amount_cents
  end

  defp open_quantity(credited, line),
    do: max(line.quantity - credited_quantity(credited, line), 1)

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
