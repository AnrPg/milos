defmodule Palee.Fiscal.Domain.SaleLines do
  @moduledoc """
  Turns a sale into the `lines` of a `Palee.Fiscal.issue/4` request
  (ADR-244). Pure and stable: callers outside Fiscal (Finance and Payments)
  build their requests with it, so the tax rules live in one place.

  ## The seller

  Every function takes the seller as `%{country_code, vat_scheme}` (atom or
  string keys), i.e. the saved identity of
  `Palee.Fiscal.identity_status/1`.

  ## Items

  `lines/2` takes a list of items:

      %{
        description: "Unlimited – monthly",   # required; cut to 300 characters
        quantity: 1,                          # default 1
        unit_price_cents: 6_000,              # required, >= 0, the price charged
        discount_cents: 0,                    # default 0, <= quantity × unit price
        tax_category: "reduced" | nil,        # the item's own category
        default_tax_category: "standard" | nil, # its parent's (a variant's product)
        exemption_reason: nil,                # needed when the category is `exempt`
        default_exemption_reason: nil,        # the parent's reason
        rate_bp: nil,                         # US `sales_tax` only, from the calculator
        source_type: "membership_package", source_id: "…uuid…"
      }

  and returns `{:ok, lines}` with request lines

      %{description, quantity, unit_price_cents, discount_cents, tax_category,
        exemption_reason, rate_bp, source_type, source_id}

  or `{:error, {:invalid_sale_line, index, reason}}` (`index` from 0;
  reasons: `:invalid_quantity`, `:invalid_amount`, `:discount_exceeds_amount`,
  `:missing_description`, `:unknown_tax_category`, `:exemption_reason_required`).

  Rules:

    * the category is the item's own, else its parent's, else `standard`
      (`sales_tax` in the US), and must be one the seller's country offers;
    * a seller that is not VAT registered (`vat_scheme` `small_business`)
      prints every line as `exempt` with its country's legal mention
      (`TaxCategories.small_business_reason/1`); an `exempt` scheme
      business keeps the items' own reasons;
    * a `sales_tax` line without `rate_bp` is left for
      `Palee.Fiscal.Taxes.apply_sales_tax/4`, which asks the
      `SalesTaxCalculator` port.

  ## Builders

    * `package_item/2` – a membership package sold (Finance);
    * `variant_item/3` – a shop variant with its product (Shop);
    * `shop_order_line_item/2` – a line of a shop order;
    * `finance_invoice/4` – a whole Finance invoice: returns the request
      fields `%{currency, prices_include_tax, source_type, source_id,
      lines}` the caller completes with `kind`, `issue_date`, `buyer`,
      `payment_method` and `idempotency_key`.
  """

  alias Palee.Fiscal.Domain.{TaxCategories, VatRates}

  @max_description 300

  @doc "Request lines for `items` sold by `seller` (see the module doc)."
  def lines(items, seller) when is_list(items) do
    country = field(seller, :country_code)
    scheme = field(seller, :vat_scheme) || "standard"

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case line(item, country, scheme) do
        {:ok, line} -> {:cont, {:ok, [line | acc]}}
        {:error, reason} -> {:halt, {:error, {:invalid_sale_line, index, reason}}}
      end
    end)
    |> case do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp line(item, country, scheme) do
    quantity = field(item, :quantity) || 1
    unit = field(item, :unit_price_cents)
    discount = field(item, :discount_cents) || 0
    description = item |> field(:description) |> TaxCategories.clean()

    category =
      TaxCategories.effective(
        field(item, :tax_category),
        field(item, :default_tax_category),
        country
      )

    reason =
      TaxCategories.clean(field(item, :exemption_reason)) ||
        TaxCategories.clean(field(item, :default_exemption_reason))

    {category, reason} = scheme_override(scheme, country, category, reason)

    cond do
      not (is_integer(quantity) and quantity > 0) ->
        {:error, :invalid_quantity}

      not (is_integer(unit) and unit >= 0 and is_integer(discount) and discount >= 0) ->
        {:error, :invalid_amount}

      discount > quantity * unit ->
        {:error, :discount_exceeds_amount}

      is_nil(description) ->
        {:error, :missing_description}

      category not in VatRates.categories(country) ->
        {:error, :unknown_tax_category}

      category == "exempt" and is_nil(reason) ->
        {:error, :exemption_reason_required}

      true ->
        {:ok,
         %{
           description: String.slice(description, 0, @max_description),
           quantity: quantity,
           unit_price_cents: unit,
           discount_cents: discount,
           tax_category: category,
           exemption_reason:
             if(category == "exempt", do: String.slice(reason, 0, TaxCategories.max_reason())),
           rate_bp: if(category == "sales_tax", do: field(item, :rate_bp)),
           source_type: field(item, :source_type),
           source_id: field(item, :source_id)
         }}
    end
  end

  defp scheme_override("small_business", country, _category, _reason),
    do: {"exempt", TaxCategories.small_business_reason(country)}

  defp scheme_override("exempt", _country, _category, reason), do: {"exempt", reason}
  defp scheme_override(_scheme, _country, category, reason), do: {category, reason}

  # ── Builders ──────────────────────────────────────────────────────────────

  @doc """
  An item for a membership package (`%{id, name, base_price_cents,
  tax_category, exemption_reason}`). Options: `:quantity`,
  `:unit_price_cents` (default the base price), `:discount_cents`,
  `:description` (default the name).
  """
  def package_item(package, opts \\ []) do
    %{
      description: Keyword.get(opts, :description) || field(package, :name),
      quantity: Keyword.get(opts, :quantity, 1),
      unit_price_cents: Keyword.get(opts, :unit_price_cents) || field(package, :base_price_cents),
      discount_cents: Keyword.get(opts, :discount_cents, 0),
      tax_category: field(package, :tax_category),
      exemption_reason: field(package, :exemption_reason),
      source_type: "membership_package",
      source_id: field(package, :id)
    }
  end

  @doc """
  An item for a shop variant of `product` (`%{id, title, tax_category,
  exemption_reason}`; the variant `%{id, title, price_cents, tax_category,
  exemption_reason}` overrides the product's category). Options as
  `package_item/2`.
  """
  def variant_item(product, variant, opts \\ []) do
    title =
      [field(product, :title), field(variant, :title)]
      |> Enum.map(&TaxCategories.clean/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(" – ")

    %{
      description: Keyword.get(opts, :description) || title,
      quantity: Keyword.get(opts, :quantity, 1),
      unit_price_cents: Keyword.get(opts, :unit_price_cents) || field(variant, :price_cents),
      discount_cents: Keyword.get(opts, :discount_cents, 0),
      tax_category: field(variant, :tax_category),
      default_tax_category: field(product, :tax_category),
      exemption_reason: field(variant, :exemption_reason),
      default_exemption_reason: field(product, :exemption_reason),
      source_type: "shop_variant",
      source_id: field(variant, :id)
    }
  end

  @doc """
  An item for a shop order line (its `tax_class` is the category snapshot
  taken when the order was priced). `tax` may carry the
  `exemption_reason` of an exempt product.
  """
  def shop_order_line_item(line, tax \\ %{}) do
    title =
      [field(line, :product_title), field(line, :variant_title)]
      |> Enum.map(&TaxCategories.clean/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join(" – ")

    %{
      description: title,
      quantity: field(line, :quantity),
      unit_price_cents: field(line, :unit_price_cents),
      discount_cents: field(line, :discount_cents) || 0,
      tax_category: field(tax, :tax_category) || field(line, :tax_class),
      exemption_reason: field(tax, :exemption_reason),
      source_type: "shop_order_line",
      source_id: field(line, :id)
    }
  end

  @doc """
  The fiscal request fields of a Finance invoice and its lines.

  `taxes` says the category of each line, by the first that matches:

      %{
        sources: %{source_id => tax},         # e.g. shop items by order line id
        packages: %{code_or_subscription_id => tax}, # by `package_code_snapshot`
                                              # or `membership_package_subscription_id`
        charges: %{charge_category => tax},   # manual charges ("product", "event", …)
        default: tax                          # anything else
      }

  where `tax` is `%{tax_category, exemption_reason}`. Without a match a
  line gets the country's default category.

  `{:ok, %{currency, prices_include_tax: true, source_type:
  "finance_invoice", source_id, lines}}` or the error of `lines/2`.
  """
  def finance_invoice(invoice, invoice_lines, taxes, seller) do
    items =
      Enum.map(invoice_lines, fn line ->
        tax = invoice_line_tax(line, taxes || %{})

        %{
          description: field(line, :description),
          quantity: field(line, :quantity) || 1,
          unit_price_cents: field(line, :unit_amount_cents),
          discount_cents: field(line, :discount_cents) || 0,
          tax_category: field(tax, :tax_category),
          exemption_reason: field(tax, :exemption_reason),
          source_type: "finance_invoice_line",
          source_id: field(line, :id)
        }
      end)

    with {:ok, lines} <- lines(items, seller) do
      {:ok,
       %{
         currency: field(invoice, :currency),
         prices_include_tax: true,
         source_type: "finance_invoice",
         source_id: field(invoice, :id),
         lines: lines
       }}
    end
  end

  @doc """
  The lines of a payment of part of a sale (ADR-262): `amount_cents` of the
  gross of `lines` (request lines of the whole sale), split across its tax
  groups in proportion to each group's gross (largest remainder, so the
  parts add up to the amount exactly). One line per group, described as
  `description`. A payment of the whole gross returns `lines` unchanged.

  `{:ok, lines}`, or `{:error, :invalid_amount}` for an amount of zero or
  more than the sale.
  """
  def payment_part(lines, amount_cents, description) when is_list(lines) do
    total = Enum.sum(Enum.map(lines, &line_gross/1))

    cond do
      not (is_integer(amount_cents) and amount_cents > 0 and amount_cents <= total) ->
        {:error, :invalid_amount}

      amount_cents == total ->
        {:ok, lines}

      true ->
        {:ok, allocate(tax_groups(lines), amount_cents, total, description)}
    end
  end

  @doc """
  ADR-264: lines for money charged on top of a sale that follows the
  sale's taxes (a card surcharge is part of the price of what it is paid
  for): `amount_cents` split across the tax groups of `lines` in
  proportion to each group's gross, one line per group, described as
  `description`. The amount may be any positive size.

  `{:ok, lines}`, or `{:error, :invalid_amount}` for an amount of zero or
  a sale with no gross to follow.
  """
  def follow_sale(lines, amount_cents, description) when is_list(lines) do
    total = Enum.sum(Enum.map(lines, &line_gross/1))

    if is_integer(amount_cents) and amount_cents > 0 and total > 0,
      do: {:ok, allocate(tax_groups(lines), amount_cents, total, description)},
      else: {:error, :invalid_amount}
  end

  defp tax_groups(lines) do
    lines
    |> Enum.group_by(&{&1.tax_category, &1.exemption_reason, &1.rate_bp})
    |> Enum.map(fn {key, group} -> {key, Enum.sum(Enum.map(group, &line_gross/1))} end)
    |> Enum.reject(fn {_key, gross} -> gross == 0 end)
    |> Enum.sort()
  end

  defp line_gross(line), do: line.quantity * line.unit_price_cents - (line.discount_cents || 0)

  defp allocate(groups, amount, total, description) do
    shares =
      Enum.map(groups, fn {key, gross} ->
        exact = amount * gross
        {key, div(exact, total), rem(exact, total)}
      end)

    left = amount - Enum.sum(Enum.map(shares, &elem(&1, 1)))

    bonus =
      shares
      |> Enum.with_index()
      |> Enum.sort_by(fn {{_key, _base, remainder}, index} -> {-remainder, index} end)
      |> Enum.take(left)
      |> MapSet.new(fn {_share, index} -> index end)

    shares
    |> Enum.with_index()
    |> Enum.map(fn {{{category, reason, rate_bp}, base, _remainder}, index} ->
      %{
        description: String.slice(description, 0, @max_description),
        quantity: 1,
        unit_price_cents: base + if(MapSet.member?(bonus, index), do: 1, else: 0),
        discount_cents: 0,
        tax_category: category,
        exemption_reason: reason,
        rate_bp: rate_bp,
        source_type: nil,
        source_id: nil
      }
    end)
    |> Enum.reject(&(&1.unit_price_cents == 0))
  end

  defp invoice_line_tax(line, taxes) do
    sources = field(taxes, :sources) || %{}
    packages = field(taxes, :packages) || %{}
    charges = field(taxes, :charges) || %{}

    Map.get(sources, field(line, :source_id)) ||
      Map.get(packages, field(line, :package_code_snapshot)) ||
      Map.get(packages, field(line, :membership_package_subscription_id)) ||
      Map.get(charges, field(line, :charge_category)) ||
      field(taxes, :default) || %{}
  end

  defp field(nil, _key), do: nil

  defp field(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
