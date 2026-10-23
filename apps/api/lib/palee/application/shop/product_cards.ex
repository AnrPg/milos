defmodule Palee.Application.Shop.ProductCards do
  @moduledoc """
  The product card on a «Προώθηση» post (ADR-190): a post whose attachment is
  a shop product carries, besides the snapshot taken when it was posted
  (title, price, image), the product as the reader can buy it now:

    * `status`: `available`, `sold_out`, `members_only` (the product is sold
      to members and the reader is not one) or `unavailable` (no longer
      published or sold in the app);
    * the live price range and availability (never stock counts);
    * the post's promotion code while it is redeemable, and the price with it;
    * `buy_link`: the in-app product route with the attribution an order
      placed from it records (`source: club_post`, `source_ref_id`: the post,
      the promotion code).

  Cards are read per business, in that business's tenant session.
  """

  alias Palee.{Organizations, Shop}

  @doc """
  Puts `product` on every presented post (nil unless it carries a product).
  `member_organization_ids` are the businesses the reader is a member of
  (or a function returning them, called only when a post carries a product).
  """
  def attach(posts, member_organization_ids, now \\ DateTime.utc_now()) do
    wanted = Enum.filter(posts, &(&1.attachment_type == "product" and is_map(&1.attachment)))

    if wanted == [] do
      Enum.map(posts, &Map.put_new(&1, :product, nil))
    else
      members =
        if is_function(member_organization_ids, 0),
          do: MapSet.new(member_organization_ids.()),
          else: MapSet.new(member_organization_ids)

      cards = cards(wanted, members, now)
      Enum.map(posts, &Map.put(&1, :product, Map.get(cards, &1.id)))
    end
  end

  @doc "The businesses `user_id` belongs to (for `attach/3` outside a club feed)."
  def member_organization_ids(nil), do: []

  def member_organization_ids(user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Organizations.provider_memberships()
    |> Enum.map(& &1.organization.id)
  end

  defp cards(posts, members, now) do
    posts
    |> Enum.group_by(&organization_id/1)
    |> Enum.reject(fn {organization_id, _posts} -> is_nil(organization_id) end)
    |> Enum.flat_map(fn {organization_id, posts} ->
      context = %{organization_id: organization_id}
      product_ids = posts |> Enum.map(& &1.attachment_id) |> Enum.uniq()
      products = context |> Shop.list_products(%{ids: product_ids}) |> Map.new(&{&1.id, &1})

      codes =
        case posts |> Enum.map(&snapshot(&1, "promotion_code_id")) |> Enum.filter(&is_binary/1) do
          [] ->
            %{}

          ids ->
            context |> Shop.list_promotion_codes(%{ids: Enum.uniq(ids)}) |> Map.new(&{&1.id, &1})
        end

      viewer = if MapSet.member?(members, organization_id), do: :member, else: :visitor
      gated? = viewer == :visitor and gated?(organization_id)

      Enum.map(posts, fn post ->
        product = Map.get(products, post.attachment_id)
        code = Map.get(codes, snapshot(post, "promotion_code_id"))
        {post.id, card(post, product, code, viewer, gated?, now)}
      end)
    end)
    |> Map.new()
  end

  defp card(post, product, code, viewer, gated?, now) do
    variants = live_variants(product)
    status = status(product, variants, viewer, gated?)
    promotion = promotion(code, status, now)
    {low, high, currency} = price_range(variants, post)

    %{
      product_id: post.attachment_id,
      title: (product && product.title) || snapshot(post, "title"),
      media_ids: (product && product.media_ids) || List.wrap(snapshot(post, "media_ids")),
      status: status,
      availability: availability(variants, status),
      price_cents: low,
      max_price_cents: high,
      currency: currency,
      promotion: promotion,
      promotion_price_cents: promotion && low && low - promotion_discount(promotion, low),
      buy_link: if(status == "available", do: buy_link(post, promotion))
    }
  end

  defp live_variants(nil), do: []
  defp live_variants(product), do: Enum.filter(product.variants || [], &is_nil(&1.archived_at))

  defp status(nil, _variants, _viewer, _gated?), do: "unavailable"

  defp status(product, variants, viewer, gated?) do
    cond do
      not Shop.sellable?(product, :online) or variants == [] -> "unavailable"
      gated? -> "unavailable"
      not Shop.visible_to?(product, viewer) -> "members_only"
      Enum.all?(variants, &sold_out?/1) -> "sold_out"
      true -> "available"
    end
  end

  defp sold_out?(%{track_inventory: false}), do: false
  defp sold_out?(%{stock: %{available: available}}), do: available <= 0
  defp sold_out?(_variant), do: true

  defp availability(_variants, status) when status != "available", do: nil

  defp availability(variants, _status) do
    if Enum.any?(
         variants,
         &(Map.get(&1, :stock_status) in [:low, :critical] and not sold_out?(&1))
       ),
       do: "low",
       else: "in_stock"
  end

  defp price_range([], post),
    do:
      {snapshot(post, "price_cents"), snapshot(post, "max_price_cents"),
       snapshot(post, "currency")}

  defp price_range(variants, _post) do
    prices = Enum.map(variants, & &1.price_cents)
    {Enum.min(prices), Enum.max(prices), hd(variants).currency}
  end

  defp promotion(nil, _status, _now), do: nil
  defp promotion(_code, status, _now) when status != "available", do: nil

  defp promotion(code, _status, now) do
    if Shop.promotion_redeemable(code, now) == :ok do
      %{
        code: code.code,
        discount_percent: code.discount_percent,
        discount_cents: code.discount_cents,
        ends_at: code.ends_at
      }
    end
  end

  defp promotion_discount(%{discount_percent: percent}, price) when is_integer(percent),
    do: min(price, div(price * percent + 50, 100))

  defp promotion_discount(%{discount_cents: cents}, price) when is_integer(cents),
    do: min(price, cents)

  defp buy_link(post, promotion) do
    params =
      %{source: "club_post", source_ref_id: post.id}
      |> then(&if promotion, do: Map.put(&1, :promotion_code, promotion.code), else: &1)

    %{
      product_id: post.attachment_id,
      path: "/shop/products/#{post.attachment_id}",
      params: params,
      url: "/shop/products/#{post.attachment_id}?" <> URI.encode_query(params)
    }
  end

  defp gated?(organization_id) do
    case Organizations.get_by_id(organization_id) do
      nil -> true
      organization -> Organizations.business_gated?(organization)
    end
  end

  defp organization_id(post), do: snapshot(post, "organization_id")

  defp snapshot(%{attachment: attachment}, key) when is_map(attachment),
    do: Map.get(attachment, key)

  defp snapshot(_post, _key), do: nil
end
