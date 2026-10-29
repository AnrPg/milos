defmodule Palee.Fiscal.Domain.MyDataInvoice do
  @moduledoc """
  Maps a fiscal document to the myDATA invoice the Greek tax authority
  (AADE) expects (ADR-243). Pure: the result is an ordered element tree
  (`[{name, value_or_children}]`) in the order of the official XSD
  (`priv/fiscal/mydata/v2.0.1/InvoicesDoc-v2.0.1.xsd`); an infrastructure
  codec writes it as XML.

  Document types (AADE code list):

    * receipt → `11.2` ΑΠΥ (services) or `11.1` ΑΛΠ (any goods line);
    * invoice → `2.1`/`2.2`/`2.3` ΤΠΥ (services: Greek, EU, other buyer) or
      `1.1`/`1.2`/`1.3` (goods);
    * credit note of a receipt → `11.4`; of an invoice → `5.1`, which
      carries the MARK of the invoice it corrects (`correlatedInvoices`).

  Amounts in myDATA are positive, also on credit notes: the type says the
  sign. Income classification is E3_561_003 (retail), E3_561_001 (domestic
  B2B), E3_561_005 (EU) or E3_561_006 (other countries), with category
  `category1_1` (goods) or `category1_3` (services).
  """

  @goods_sources ~w(shop_order_item product)
  @eu ~w(AT BE BG CY CZ DE DK EE ES FI FR HR HU IE IT LT LU LV MT NL PL PT RO SE SI SK)

  # AADE vatCategory by rate (basis points).
  @vat_categories %{2400 => 1, 1300 => 2, 600 => 3, 1700 => 4, 900 => 5, 400 => 6, 300 => 9}

  # AADE vatExemptionCategory by article of the Greek VAT code (ν. 2859/2000).
  @exemption_articles %{
    "2" => 1,
    "3" => 1,
    "5" => 2,
    "13" => 3,
    "14" => 4,
    "16" => 5,
    "19" => 6,
    "22" => 7,
    "24" => 8,
    "25" => 9,
    "26" => 10,
    "27" => 11,
    "28" => 14,
    "39" => 15,
    "39α" => 16,
    "39a" => 16,
    "40" => 17,
    "41" => 18,
    "47" => 19,
    "43" => 20,
    "44" => 21,
    "45" => 22,
    "46" => 23,
    "6" => 24
  }
  @small_business_exemption 15

  # AADE payment method types.
  @payment_types %{
    "cash" => 3,
    "card" => 7,
    "online" => 7,
    "bank_transfer" => 1,
    "other" => 5
  }
  @on_credit 5

  @doc "The myDATA invoice type of `document` (credit notes need the original's kind)."
  def invoice_type(document, original_kind \\ nil)

  def invoice_type(%{kind: "receipt"} = document, _original_kind),
    do: if(goods?(document), do: "11.1", else: "11.2")

  def invoice_type(%{kind: "invoice"} = document, _original_kind) do
    family = if goods?(document), do: "1", else: "2"
    family <> "." <> Integer.to_string(buyer_zone(document))
  end

  def invoice_type(%{kind: "credit_note"}, "receipt"), do: "11.4"
  def invoice_type(%{kind: "credit_note"}, "invoice"), do: "5.1"
  def invoice_type(_document, _original_kind), do: nil

  @doc "The AADE vatCategory of a line, or an error naming what is missing."
  def vat_category(%{tax_category: "exempt"}), do: {:ok, 7}

  def vat_category(%{rate_bp: rate}) do
    case Map.fetch(@vat_categories, rate) do
      {:ok, category} -> {:ok, category}
      :error -> {:error, :mydata_unsupported_vat_rate}
    end
  end

  @doc """
  The AADE vatExemptionCategory of an exempt line: the article named in
  its exemption reason («άρθρο 22», «άρθ. 39α», «article 39»), else
  article 39 for a small business, else an error.
  """
  def exemption_category(reason, vat_scheme) do
    case article(reason) do
      nil when vat_scheme == "small_business" -> {:ok, @small_business_exemption}
      nil -> {:error, :mydata_exemption_article_required}
      article -> Map.fetch(@exemption_articles, article) |> exemption_result()
    end
  end

  defp exemption_result({:ok, category}), do: {:ok, category}
  defp exemption_result(:error), do: {:error, :mydata_unknown_exemption_article}

  defp article(nil), do: nil

  defp article(reason) do
    case Regex.run(
           ~r/(?:[άα]ρθρ[οα]?|[άα]ρθ|article|art)\.?\s*(\d+)(?:\s*([αa])(?!\p{L}))?/iu,
           reason
         ) do
      [_, number] -> number
      [_, number, letter] -> number <> String.downcase(letter)
      nil -> nil
    end
  end

  @doc """
  `{:ok, tree}` of one `invoice` element, or `{:error, reason}`.

  `opts`:
    * `:original` – for a credit note, `%{kind, mark}` of the document it
      corrects (`mark` required when the original is an invoice);
    * `:payment` – card details from the POS provider (`transaction_id`,
      `tid`, `providers_signature`) when the payment went through a
      terminal linked to Palee.
  """
  def build(document, opts \\ []) do
    original = opts[:original]
    original_kind = original && original[:kind]
    seller = document.seller

    with :ok <- greek_seller(seller),
         type when is_binary(type) <-
           invoice_type(document, original_kind) || {:error, :mydata_unknown_type},
         {:ok, correlated} <- correlated(type, original),
         {:ok, details} <- details(document, type) do
      {:ok,
       [
         {"issuer", party(seller, field(seller, :branch_code) || 0, true)}
       ] ++
         counterpart(type, document.buyer) ++
         [
           {"invoiceHeader",
            [
              {"series", document.series},
              {"aa", Integer.to_string(document.sequence)},
              {"issueDate", Date.to_iso8601(document.issue_date)},
              {"invoiceType", type}
            ] ++
              currency(document.currency) ++
              Enum.map(correlated, &{"correlatedInvoices", &1})},
           {"paymentMethods", [{"paymentMethodDetails", payment(document, opts[:payment])}]}
         ] ++
         Enum.map(details, &{"invoiceDetails", &1.tree}) ++
         [{"invoiceSummary", summary(details, document)}]}
    end
  end

  # ── Parties ─────────────────────────────────────────────────────────────

  defp greek_seller(seller) do
    if field(seller, :country_code) == "GR" and vat_number(seller) != nil,
      do: :ok,
      else: {:error, :mydata_seller_not_greek}
  end

  # AADE refuses names of Greek parties (it knows them by ΑΦΜ).
  defp party(party, branch, issuer?) do
    country = field(party, :country_code)

    [
      {"vatNumber", vat_number(party)},
      {"country", country},
      {"branch", Integer.to_string(branch)}
    ] ++
      if(country != "GR",
        do: [{"name", field(party, :name) || field(party, :legal_name)}],
        else: []
      ) ++
      if(issuer? and country == "GR", do: [], else: address(party))
  end

  defp counterpart(type, buyer) when type in ["11.1", "11.2", "11.4"] or is_nil(buyer), do: []
  defp counterpart(_type, buyer), do: [{"counterpart", party(buyer, 0, false)}]

  defp address(party) do
    case {field(party, :postal_code), field(party, :city)} do
      {postal_code, city} when is_binary(postal_code) and is_binary(city) ->
        [
          {"address",
           optional("street", field(party, :street)) ++
             optional("number", field(party, :building_number)) ++
             [{"postalCode", postal_code}, {"city", city}]}
        ]

      _missing ->
        []
    end
  end

  defp vat_number(party) do
    case field(party, :vat_number) || field(party, :tax_id) do
      nil -> nil
      number -> number |> String.replace(~r/[\s.\-]/u, "") |> strip_prefix()
    end
  end

  defp strip_prefix(<<prefix::binary-size(2), rest::binary>> = number) do
    if prefix =~ ~r/^[A-Z]{2}$/ and rest =~ ~r/^\d/, do: rest, else: number
  end

  defp strip_prefix(number), do: number

  defp buyer_zone(%{buyer: buyer}) do
    case buyer && field(buyer, :country_code) do
      "GR" -> 1
      country when country in @eu -> 2
      nil -> 1
      _other -> 3
    end
  end

  # ── Header and payment ─────────────────────────────────────────────────

  defp correlated("5.1", %{mark: mark}) when is_binary(mark) and mark != "", do: {:ok, [mark]}
  defp correlated("5.1", _original), do: {:error, :mydata_original_not_transmitted}
  defp correlated("11.4", %{mark: mark}) when is_binary(mark) and mark != "", do: {:ok, [mark]}
  defp correlated(_type, _original), do: {:ok, []}

  defp currency("EUR"), do: []
  defp currency(currency), do: [{"currency", currency}]

  defp payment(document, pos) do
    [
      {"type",
       document.payment_method
       |> then(&Map.get(@payment_types, &1, @on_credit))
       |> Integer.to_string()},
      {"amount", amount(document.gross_cents)}
    ] ++
      if(is_map(pos) and document.payment_method in ["card", "online"],
        do:
          optional("transactionId", pos[:transaction_id]) ++
            optional("tid", pos[:tid]) ++
            provider_signature(pos[:providers_signature]),
        else: []
      )
  end

  defp provider_signature(%{signing_author: author, signature: signature}),
    do: [{"ProvidersSignature", [{"SigningAuthor", author}, {"Signature", signature}]}]

  defp provider_signature(_signature), do: []

  # ── Lines and totals ───────────────────────────────────────────────────

  defp details(document, type) do
    scheme = field(document.seller, :vat_scheme)

    document.lines
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      with {:ok, vat_category} <- vat_category(line),
           {:ok, exemption} <- exemption(line, vat_category, scheme) do
        {:cont,
         {:ok,
          [
            %{
              position: line.position,
              net_cents: line.net_cents,
              tax_cents: line.tax_cents,
              vat_category: vat_category,
              exemption: exemption,
              classification: line_classification(type, line)
            }
            | acc
          ]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, details} -> {:ok, details |> Enum.reverse() |> Enum.map(&detail_tree/1)}
      error -> error
    end
  end

  defp exemption(line, 7, scheme), do: exemption_category(line.exemption_reason, scheme)

  defp exemption(_line, _category, _scheme), do: {:ok, nil}

  defp detail_tree(detail) do
    %{
      tree:
        [
          {"lineNumber", Integer.to_string(detail.position)},
          {"netValue", amount(detail.net_cents)},
          {"vatCategory", Integer.to_string(detail.vat_category)},
          {"vatAmount", amount(detail.tax_cents)}
        ] ++
          if(detail.exemption,
            do: [{"vatExemptionCategory", Integer.to_string(detail.exemption)}],
            else: []
          ) ++
          [{"incomeClassification", classification_tree(detail.classification, detail.net_cents)}],
      net_cents: detail.net_cents,
      tax_cents: detail.tax_cents,
      classification: detail.classification
    }
  end

  defp summary(details, document) do
    net = Enum.sum(Enum.map(details, & &1.net_cents))
    tax = Enum.sum(Enum.map(details, & &1.tax_cents))

    totals =
      details
      |> Enum.group_by(& &1.classification, & &1.net_cents)
      |> Enum.sort()
      |> Enum.map(fn {classification, nets} ->
        {"incomeClassification", classification_tree(classification, Enum.sum(nets))}
      end)

    [
      {"totalNetValue", amount(net)},
      {"totalVatAmount", amount(tax)},
      {"totalWithheldAmount", "0.00"},
      {"totalFeesAmount", "0.00"},
      {"totalStampDutyAmount", "0.00"},
      {"totalOtherTaxesAmount", "0.00"},
      {"totalDeductionsAmount", "0.00"},
      {"totalGrossValue", amount(document.gross_cents)}
    ] ++ totals
  end

  defp line_classification(type, line) do
    {classification_type(type), if(goods_line?(line), do: "category1_1", else: "category1_3")}
  end

  defp classification_type(type) when type in ["11.1", "11.2", "11.4"], do: "E3_561_003"
  defp classification_type(type) when type in ["1.2", "2.2"], do: "E3_561_005"
  defp classification_type(type) when type in ["1.3", "2.3"], do: "E3_561_006"
  defp classification_type(_type), do: "E3_561_001"

  defp classification_tree({type, category}, net_cents),
    do: [
      {{:icls, "classificationType"}, type},
      {{:icls, "classificationCategory"}, category},
      {{:icls, "amount"}, amount(net_cents)}
    ]

  defp goods?(document), do: Enum.any?(document.lines, &goods_line?/1)
  defp goods_line?(line), do: line[:source_type] in @goods_sources

  @doc "Cents as an AADE amount: `1234` → `\"12.34\"`."
  def amount(cents) when is_integer(cents) and cents >= 0 do
    "#{div(cents, 100)}.#{cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  defp optional(_name, nil), do: []
  defp optional(_name, ""), do: []
  defp optional(name, value), do: [{name, to_string(value)}]

  # Snapshots load from JSONB with string keys and are built with atom keys.
  defp field(nil, _key), do: nil

  defp field(map, key) do
    case Map.get(map, key, Map.get(map, Atom.to_string(key))) do
      "" -> nil
      value -> value
    end
  end
end
