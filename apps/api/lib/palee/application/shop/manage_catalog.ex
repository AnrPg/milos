defmodule Palee.Application.Shop.ManageCatalog do
  @moduledoc """
  Staff use cases of the shop catalog (ADR-190): create and edit products
  and their variants, publish, unpublish and archive.

    * Photos are ready `box_photo` media of the business (ADR-148).
    * A product is a covering item (ADR-186 §8): valid at every branch or
      at some; branch-scoped staff see and change only the ones inside their
      branches, and their new products default to their branches.
    * Publishing an `anyone` product reaches people outside the business,
      so a demo business (ADR-184) cannot (`business_not_activated`). It can
      still build the catalog and publish it to its (mock) members.
    * Every price, compare-at or cost change of a variant goes through
      `save_variant/4`, which emits `shop_variant_price_changed`: the one
      source of the price history.
  """

  alias Palee.Application.{CoveringBranches, GoLive}
  alias Palee.Application.Shop.Observability
  alias Palee.{Media, Shop}

  @price_fields [:price_cents, :compare_at_price_cents, :cost_price_cents, :currency]

  @doc "Products the acting staff member may see (`filters`: statuses, q, category)."
  def list(context, filters \\ %{}) do
    context
    |> Shop.list_products(Map.put_new(filters, :statuses, [:draft, :published]))
    |> then(
      &CoveringBranches.visible(context, &1, fn product -> CoveringBranches.of_row(product) end)
    )
  end

  @doc "One product, when the acting staff member may see it."
  def get(context, id) do
    with %{} = product <- Shop.get_product(context, id) || {:error, :not_found},
         :ok <- visible(context, product) do
      {:ok, product}
    end
  end

  @doc """
  A new draft product, with its variants (`variants: [%{option_values,
  price_cents, ...}]`, at least one, which may name `initial_quantity` and
  `location_id` to receive opening stock).
  """
  def create(context, params) do
    params = atomize(params)

    with {:ok, target} <- CoveringBranches.for_new(context, CoveringBranches.requested(params)),
         :ok <- ready_media(context, params[:media_ids]),
         {:ok, options} <- Shop.normalize_options(params[:options]),
         variants when is_list(variants) and variants != [] <-
           params[:variants] || [%{price_cents: params[:price_cents]}],
         {:ok, product} <-
           Shop.transaction(context, fn ->
             create_in_transaction(context, params, options, target, variants)
           end) do
      Observability.catalog("shop_product_created", context, product)
      Enum.each(product.variants, &Observability.price_changed(context, nil, &1))
      {:ok, product}
    else
      [] -> {:error, :product_has_no_variants}
      error -> error
    end
  end

  defp create_in_transaction(context, params, options, target, variants) do
    attrs =
      params
      |> Map.take(Shop.Product.editable())
      |> Map.put(:options, options)
      |> Map.merge(%{status: :draft, created_by_id: context.user_id})
      |> CoveringBranches.put_columns(target)

    with {:ok, product} <- Shop.save_product(context, nil, attrs),
         {:ok, saved} <- insert_variants(context, product, variants),
         :ok <- opening_stock(context, saved) do
      {:ok, Shop.get_product(context, product.id)}
    end
  end

  defp insert_variants(context, product, variants) do
    variants
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {variant, index}, {:ok, acc} ->
      variant = atomize(variant)

      case new_variant(context, product, Map.put_new(variant, :position, index)) do
        {:ok, saved} -> {:cont, {:ok, [{saved, variant} | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, saved} -> {:ok, Enum.reverse(saved)}
      error -> error
    end
  end

  # `saved` pairs each stored variant with the params it came from.
  defp opening_stock(context, saved) do
    movements =
      Enum.flat_map(saved, fn {saved, params} ->
        case params[:initial_quantity] do
          quantity when is_integer(quantity) and quantity > 0 ->
            [
              %{
                variant_id: saved.id,
                location_id: params[:location_id],
                kind: :receive,
                quantity: quantity,
                unit_cost_cents: saved.cost_price_cents,
                note: "Opening stock",
                user_id: context.user_id
              }
            ]

          _none ->
            []
        end
      end)

    with :ok <- authorize_locations(context, Enum.map(movements, & &1.location_id)),
         {:ok, %{movements: rows}} <- Shop.apply_movements(context, movements) do
      Observability.stock_moved(context, rows)
      _ = Shop.refresh_stock_status(context, Enum.map(movements, & &1.variant_id))
      :ok
    end
  end

  defp new_variant(context, product, params) do
    with {:ok, values} <- Shop.validate_option_values(product.options, params[:option_values]) do
      attrs =
        params
        |> Map.take(Shop.Variant.editable())
        |> Map.merge(%{
          product_id: product.id,
          option_values: values,
          title: params[:title] || Shop.variant_title(product.options, values)
        })

      Shop.save_variant(context, nil, attrs)
    end
  end

  @doc "Edits a product's details (not its status: see `set_status/3`)."
  def update(context, id, params) do
    params = atomize(params)

    with {:ok, product} <- get(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(product)),
         {:ok, attrs} <- covering_change(context, params),
         :ok <- ready_media(context, params[:media_ids]),
         {:ok, attrs} <- options_change(product, attrs),
         :ok <- still_publishable(context, product, attrs) do
      Shop.save_product(context, id, attrs)
    end
  end

  defp covering_change(context, params) do
    attrs = Map.take(params, Shop.Product.editable())

    case CoveringBranches.requested(params) do
      nil ->
        {:ok, Map.drop(attrs, [:all_locations, :location_ids])}

      requested ->
        target = CoveringBranches.target(requested)

        with :ok <- CoveringBranches.authorize(context, target),
             do: {:ok, CoveringBranches.put_columns(attrs, target)}
    end
  end

  defp options_change(product, %{options: options} = attrs) do
    with {:ok, normalized} <- Shop.normalize_options(options),
         true <-
           Enum.all?(product.variants, fn variant ->
             not is_nil(variant.archived_at) or
               match?({:ok, _}, Shop.validate_option_values(normalized, variant.option_values))
           end) || {:error, :options_in_use} do
      {:ok, %{attrs | options: normalized}}
    end
  end

  defp options_change(_product, attrs), do: {:ok, attrs}

  # A published product that becomes public is a going-live action too.
  defp still_publishable(context, %{status: :published} = product, attrs) do
    if Shop.public_product?(Map.merge(product, Map.take(attrs, [:visibility]))) and
         not Shop.public_product?(product),
       do: GoLive.check(context, :publish_profile),
       else: :ok
  end

  defp still_publishable(_context, _product, _attrs), do: :ok

  @doc "Publishes (`published`), unpublishes (`draft`) or archives (`archived`) a product."
  def set_status(context, id, status, now \\ DateTime.utc_now()) do
    with {:ok, status} <- parse_status(status),
         {:ok, product} <- get(context, id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(product)),
         :ok <- Shop.product_transition(product.status, status),
         :ok <- publish_check(context, product, status),
         {:ok, saved} <- Shop.save_product(context, id, status_attrs(product, status, now)) do
      Observability.catalog("shop_product_status_changed", context, saved, %{
        previous: product.status
      })

      {:ok, saved}
    end
  end

  defp publish_check(context, product, :published) do
    with :ok <- Shop.publishable(product, product.variants) do
      if Shop.public_product?(product), do: GoLive.check(context, :publish_profile), else: :ok
    end
  end

  defp publish_check(_context, _product, _status), do: :ok

  defp status_attrs(product, :published, now),
    do: %{status: :published, published_at: product.published_at || now, archived_at: nil}

  defp status_attrs(_product, :archived, now), do: %{status: :archived, archived_at: now}
  defp status_attrs(_product, :draft, _now), do: %{status: :draft, archived_at: nil}

  defp parse_status(status) when is_atom(status) and not is_nil(status),
    do:
      if(status in Shop.product_statuses(),
        do: {:ok, status},
        else: {:error, :invalid_product_status}
      )

  defp parse_status(status) when is_binary(status) do
    case Enum.find(Shop.product_statuses(), &(Atom.to_string(&1) == status)) do
      nil -> {:error, :invalid_product_status}
      found -> {:ok, found}
    end
  end

  defp parse_status(_status), do: {:error, :invalid_product_status}

  @doc """
  Adds (`variant_id` nil) or edits a variant. The only way a price changes:
  any change of price, compare-at, cost or currency emits
  `shop_variant_price_changed` with the previous values.
  """
  def save_variant(context, product_id, variant_id, params) do
    params = atomize(params)

    with {:ok, product} <- get(context, product_id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(product)),
         {:ok, before} <- existing_variant(product, variant_id),
         {:ok, saved} <- write_variant(context, product, before, params) do
      if price_changed?(before, saved), do: Observability.price_changed(context, before, saved)
      _ = alert_stock(context, Shop.refresh_stock_status(context, [saved.id]))
      {:ok, Shop.get_variant(context, saved.id)}
    end
  end

  defp existing_variant(_product, nil), do: {:ok, nil}

  defp existing_variant(product, id) do
    case Enum.find(product.variants, &(&1.id == id)) do
      nil -> {:error, :not_found}
      variant -> {:ok, variant}
    end
  end

  defp write_variant(context, product, nil, params), do: new_variant(context, product, params)

  defp write_variant(context, product, before, params) do
    with {:ok, attrs} <- variant_option_change(product, params) do
      attrs = Map.merge(Map.take(params, Shop.Variant.editable() -- [:option_values]), attrs)
      Shop.save_variant(context, before.id, attrs)
    end
  end

  defp variant_option_change(product, %{option_values: values}) when is_map(values) do
    with {:ok, values} <- Shop.validate_option_values(product.options, values),
         do: {:ok, %{option_values: values, title: Shop.variant_title(product.options, values)}}
  end

  defp variant_option_change(_product, _params), do: {:ok, %{}}

  @doc "Archives a variant (it stays on past orders; the product keeps the others)."
  def archive_variant(context, product_id, variant_id, now \\ DateTime.utc_now()) do
    with {:ok, product} <- get(context, product_id),
         :ok <- CoveringBranches.authorize(context, CoveringBranches.of_row(product)),
         {:ok, %{}} <- existing_variant(product, variant_id) do
      Shop.save_variant(context, variant_id, %{archived_at: now})
    end
  end

  defp price_changed?(nil, _saved), do: true

  defp price_changed?(before, saved),
    do: Enum.any?(@price_fields, &(Map.get(before, &1) != Map.get(saved, &1)))

  @doc "Sends low-stock alerts for status changes that got worse."
  def alert_stock(context, changes) do
    Enum.each(changes, fn %{variant: variant, previous: previous, assessment: assessment} = change ->
      Observability.stock_status_changed(context, change)

      if Shop.stock_alert?(previous, assessment.status) do
        product = Shop.get_product(context, variant.product_id)

        Shop.notifier().stock_low(context, %{
          product_id: variant.product_id,
          variant_id: variant.id,
          product_title: product && product.title,
          variant_title: variant.title,
          status: assessment.status,
          available: variant.stock.available,
          days_left: assessment.days_left
        })
      end
    end)
  end

  defp visible(context, product) do
    if CoveringBranches.visible(context, [product], &CoveringBranches.of_row/1) == [],
      do: {:error, :not_found},
      else: :ok
  end

  defp ready_media(_context, nil), do: :ok
  defp ready_media(_context, []), do: :ok

  defp ready_media(context, ids) when is_list(ids) do
    case Media.fetch_ready(context, "box_photo", ids) do
      {:ok, _media} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ready_media(_context, _ids), do: {:error, :invalid_media}

  defp authorize_locations(context, ids) do
    ids
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn id, :ok ->
      case Palee.Organizations.authorize_location(context, id) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @known ~w(title description category media_ids options visibility sell_in_app sell_at_desk
            member_discount_applies per_person_limit all_locations location_ids position variants
            price_cents option_values sku barcode currency compare_at_price_cents cost_price_cents
            tax_class low_stock_threshold track_inventory initial_quantity location_id)a

  @doc false
  def atomize(params) when is_map(params) do
    Map.new(params, fn
      {key, value} when is_atom(key) ->
        {key, value}

      {key, value} when is_binary(key) ->
        case Enum.find(@known, &(Atom.to_string(&1) == key)) do
          nil -> {key, value}
          atom -> {atom, value}
        end
    end)
  end
end
