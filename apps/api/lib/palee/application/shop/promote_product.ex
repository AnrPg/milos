defmodule Palee.Application.Shop.PromoteProduct do
  @moduledoc """
  «Προώθηση» (ADR-190): staff announce a product with a club post whose
  attachment is the product, optionally with a promotion code of that
  product.

  Where the post goes (`target`):

    * `announcements` (default): the club's #ανακοινώσεις;
    * `channel`: a member group or PT squad of the club (`channel_id`), when
      the promoter may post there;
    * `feed`: #ανακοινώσεις made public (ADR-142), so it also shows on the box
      page and to the box's followers.

  The post carries the product's snapshot (title, images, price range,
  promotion) and is read with the live card (`ProductCards`). Its buy link
  makes the order record `source: club_post` and the post. The code (new or
  existing) and the post are written in one transaction; the code remembers
  the post that announced it.

  Only a published product sold in the app can be promoted.
  """

  alias Palee.Application.{ClubScope, PostPresenter, RealtimePublisher}
  alias Palee.Application.Shop.{Observability, ProductCards}
  alias Palee.{Community, Shop}

  @targets ~w(announcements channel feed)
  @code_fields [:code, :discount_percent, :discount_cents, :max_redemptions, :starts_at, :ends_at]

  def targets, do: @targets

  @doc """
  Promotes `product_id`. `params`: `target`, `channel_id`, `body`, and either
  `promotion_code` (a new code: `code`, `discount_percent` or
  `discount_cents`, `max_redemptions`, `starts_at`, `ends_at`) or
  `promotion_code_id` (an existing code of the product).
  Returns `{:ok, %{post, promotion_code}}` with the presented post.
  """
  def promote(context, product_id, params) do
    target = to_string(params[:target] || "announcements")

    with true <- target in @targets || {:error, :invalid_promotion_target},
         %{} = product <- Shop.get_product(context, product_id) || {:error, :not_found},
         :ok <- promotable(product),
         {:ok, club} <- ClubScope.gym_club(context),
         {:ok, channel, audience} <- destination(club, target, params[:channel_id]),
         {:ok, %{post: post, code: code}} <-
           Shop.transaction(context, fn ->
             write(context, club, channel, audience, product, params)
           end) do
      RealtimePublisher.broadcast("community:club:#{club.id}", "post_created", %{
        post_id: post.id,
        channel_id: channel.id
      })

      Observability.catalog("shop_product_promoted", context, product, %{
        post_id: post.id,
        target: target,
        channel_id: channel.id,
        promotion_code_id: code && code.id
      })

      {:ok, %{post: present(context, club, post), promotion_code: code}}
    end
  end

  @doc "The product's promotion codes with their redemptions and status."
  def list_codes(context, filters) do
    now = DateTime.utc_now()

    context
    |> Shop.list_promotion_codes(filters)
    |> Enum.map(&Map.put(&1, :status, Shop.promotion_status(&1, now)))
  end

  @doc "Changes a code's discount, window, cap or `active` (to switch it off)."
  def update_code(context, id, params) do
    with {:ok, code} <-
           Shop.save_promotion_code(context, id, Map.take(params, @code_fields ++ [:active])) do
      {:ok, Map.put(code, :status, Shop.promotion_status(code, DateTime.utc_now()))}
    end
  end

  # ── Internals ──────────────────────────────────────────────────────────

  defp promotable(product) do
    if Shop.sellable?(product, :online) and
         Enum.any?(product.variants || [], &is_nil(&1.archived_at)),
       do: :ok,
       else: {:error, :product_not_promotable}
  end

  defp destination(club, "channel", channel_id) when is_binary(channel_id) do
    case Enum.find(club.channels, &(&1.id == channel_id)) do
      %{kind: kind} = channel when kind in ["member_group", "pt_squad"] ->
        {:ok, channel, "club_channel"}

      _other ->
        {:error, :invalid_promotion_target}
    end
  end

  defp destination(_club, "channel", _channel_id), do: {:error, :invalid_promotion_target}

  defp destination(club, target, _channel_id) do
    case Enum.find(club.channels, &(&1.kind == "announcements")) do
      nil -> {:error, :invalid_promotion_target}
      channel -> {:ok, channel, if(target == "feed", do: "public", else: "club_channel")}
    end
  end

  defp write(context, club, channel, audience, product, params) do
    with {:ok, code} <- code(context, product, params),
         {:ok, post} <-
           Community.create_post(
             ClubScope.write_context(club, context),
             channel,
             club.role,
             channel.participant,
             %{
               audience: audience,
               body: params[:body],
               attachment_type: "product",
               attachment_id: product.id,
               attachment: snapshot(context, product, code)
             }
           ),
         {:ok, code} <- link(context, code, post) do
      {:ok, %{post: post, code: code}}
    end
  end

  defp code(context, product, %{promotion_code_id: id}) when is_binary(id) do
    case Shop.get_promotion_code(context, id, by: :id) do
      %{product_id: product_id} = code when product_id == product.id -> {:ok, code}
      _other -> {:error, :promotion_code_invalid}
    end
  end

  defp code(context, product, %{promotion_code: %{} = attrs}) do
    attrs
    |> Map.take(@code_fields)
    |> Map.merge(%{product_id: product.id, created_by_id: context.user_id})
    |> then(&Shop.save_promotion_code(context, nil, &1))
  end

  defp code(_context, _product, _params), do: {:ok, nil}

  defp link(_context, nil, _post), do: {:ok, nil}
  defp link(_context, %{post_id: post_id} = code, _post) when is_binary(post_id), do: {:ok, code}

  defp link(context, code, post),
    do: Shop.save_promotion_code(context, code.id, %{post_id: post.id})

  defp snapshot(context, product, code) do
    prices =
      product.variants |> Enum.filter(&is_nil(&1.archived_at)) |> Enum.map(& &1.price_cents)

    %{
      "organization_id" => context.organization_id,
      "title" => product.title,
      "media_ids" => product.media_ids,
      "price_cents" => Enum.min(prices),
      "max_price_cents" => Enum.max(prices),
      "currency" => hd(product.variants).currency,
      "promotion_code_id" => code && code.id,
      "promotion_code" => code && code.code,
      "discount_percent" => code && code.discount_percent,
      "discount_cents" => code && code.discount_cents
    }
  end

  defp present(context, club, post) do
    {:ok, post} = Community.find_post(context, post.id)

    [post]
    |> PostPresenter.posts([club], context.user_id)
    |> ProductCards.attach([context.organization_id])
    |> hd()
  end
end
