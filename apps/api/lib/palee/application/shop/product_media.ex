defmodule Palee.Application.Shop.ProductMedia do
  @moduledoc """
  Product photos (ADR-190, ADR-148): ready `shop_product_photo` uploads of
  the business, or photos of its gallery (`box_photo`). Both are public
  tenant media, so their URLs are stable and readable by members and
  visitors alike.

  `attach/2` puts `media: [%{id, url, thumb_url, full_url, width, height,
  alt_text}]` on products (in `media_ids` order, unknown or unready ids
  left out), for the staff console and the member shop.
  """

  alias Palee.Application.MediaUrls
  alias Palee.Media

  @purposes ["shop_product_photo", "box_photo"]

  def purposes, do: @purposes

  @doc "`:ok` when every id is a ready product or gallery photo of the business."
  def check_ready(_context, nil), do: :ok
  def check_ready(_context, []), do: :ok

  def check_ready(context, ids) when is_list(ids) do
    found = context |> Media.list(:tenant, Enum.uniq(ids)) |> Map.new(&{&1.id, &1})

    if Enum.all?(ids, &match?(%{status: "ready", purpose: p} when p in @purposes, found[&1])),
      do: :ok,
      else: {:error, :invalid_media}
  end

  def check_ready(_context, _ids), do: {:error, :invalid_media}

  @doc "Marks a product's photos attached, so the orphan sweep (ADR-148) keeps them."
  def mark_attached(_context, ids) when ids in [nil, []], do: :ok

  def mark_attached(context, ids) when is_list(ids) do
    _ = Media.set_attached(context, :tenant, ids, DateTime.utc_now())
    :ok
  end

  @doc "Products (maps) with their photos resolved."
  def attach(_context, []), do: []

  def attach(context, products) when is_list(products) do
    ids = products |> Enum.flat_map(&(Map.get(&1, :media_ids) || [])) |> Enum.uniq()

    presented =
      case ids do
        [] ->
          %{}

        ids ->
          context
          |> Media.list(:tenant, ids)
          |> Enum.filter(&(&1.status == "ready" and &1.purpose in @purposes))
          |> Map.new(&{&1.id, present(context, &1)})
      end

    Enum.map(products, fn product ->
      media =
        (Map.get(product, :media_ids) || []) |> Enum.map(&presented[&1]) |> Enum.reject(&is_nil/1)

      Map.put(product, :media, media)
    end)
  end

  def attach(context, product) when is_map(product), do: hd(attach(context, [product]))

  # Inspected images have one stored rendition: it is the thumb and the full.
  defp present(context, media) do
    shown = MediaUrls.present(context, media)

    %{
      id: shown.id,
      url: shown.url,
      thumb_url: Map.get(shown, :thumb_url) || shown.url,
      full_url: Map.get(shown, :full_url) || shown.url,
      width: shown.width,
      height: shown.height,
      alt_text: shown.alt_text
    }
  end
end
