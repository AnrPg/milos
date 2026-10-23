defmodule Palee.Shop.Domain.ProductPolicy do
  @moduledoc """
  The rules of a shop product (ADR-190), pure.

    * Lifecycle: a product starts as `draft`; it is `published` (the mockup's
      «Ενεργό») or `archived`. Archive, never delete: order lines keep
      pointing at it. `archived -> draft` brings one back.
    * Visibility: `members_only` (members of the business) or `anyone`
      (any Palee account, through the public box page). Publishing an
      `anyone` product reaches people outside the business, so it is a
      going-live action (ADR-184).
    * Channels: sold in the app (`sell_in_app`), at the desk
      (`sell_at_desk`), or both. At least one is on.
    * Options: at most two axes (size × colour), each with 1..50 distinct
      values; a variant names one value per axis.
  """

  @statuses [:draft, :published, :archived]
  @visibilities [:members_only, :anyone]
  @max_axes 2
  @max_values 50

  @transitions %{
    draft: [:published, :archived],
    published: [:draft, :archived],
    archived: [:draft]
  }

  @type status :: :draft | :published | :archived
  @type visibility :: :members_only | :anyone
  @type channel :: :online | :pos

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec visibilities() :: [visibility()]
  def visibilities, do: @visibilities

  @doc "`:ok` when `from -> to` is a lifecycle step."
  @spec transition(status(), status()) :: :ok | {:error, :invalid_product_transition}
  def transition(from, to) do
    if to in Map.get(@transitions, from, []), do: :ok, else: {:error, :invalid_product_transition}
  end

  @doc """
  Whether a product with these `variants` may be published: it needs a
  sellable variant and a channel.
  """
  @spec publishable(map(), [map()]) :: :ok | {:error, atom()}
  def publishable(product, variants) do
    cond do
      not Enum.any?(variants, &is_nil(Map.get(&1, :archived_at))) ->
        {:error, :product_has_no_variants}

      not channel_open?(product) ->
        {:error, :product_has_no_channel}

      true ->
        :ok
    end
  end

  @doc "Whether publishing reaches outside the business (an ADR-184 going-live action)."
  @spec public?(map()) :: boolean()
  def public?(%{visibility: visibility}), do: visibility in [:anyone, "anyone"]
  def public?(_product), do: false

  @doc "At least one channel is on."
  @spec channel_open?(map()) :: boolean()
  def channel_open?(product),
    do:
      Map.get(product, :sell_in_app, true) == true or
        Map.get(product, :sell_at_desk, true) == true

  @doc "Whether the product can be sold now through `channel`."
  @spec sellable?(map(), channel()) :: boolean()
  def sellable?(%{status: :published} = product, :online),
    do: Map.get(product, :sell_in_app) == true

  def sellable?(%{status: :published} = product, :pos),
    do: Map.get(product, :sell_at_desk) == true

  def sellable?(_product, _channel), do: false

  @doc """
  Whether a viewer sees the product in the catalog: published, sold in the
  app, and either the viewer is a member or the product is for anyone.
  """
  @spec visible_to?(map(), :member | :visitor) :: boolean()
  def visible_to?(product, viewer) do
    sellable?(product, :online) and (viewer == :member or public?(product))
  end

  @doc """
  Normalizes product options to `%{"axes" => [%{"name", "values"}]}`. Accepts
  that shape, a bare list of axes, or an empty map.
  """
  @spec normalize_options(term()) :: {:ok, map()} | {:error, atom()}
  def normalize_options(nil), do: {:ok, %{"axes" => []}}
  def normalize_options(options) when options == %{}, do: {:ok, %{"axes" => []}}

  def normalize_options(%{"axes" => axes}), do: normalize_axes(axes)
  def normalize_options(%{axes: axes}), do: normalize_axes(axes)
  def normalize_options(axes) when is_list(axes), do: normalize_axes(axes)
  def normalize_options(_options), do: {:error, :invalid_product_options}

  defp normalize_axes(axes) when is_list(axes) and length(axes) <= @max_axes do
    axes
    |> Enum.reduce_while({:ok, []}, fn axis, {:ok, acc} ->
      case normalize_axis(axis) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} ->
        normalized = Enum.reverse(normalized)
        names = Enum.map(normalized, & &1["name"])

        if length(Enum.uniq(names)) == length(names),
          do: {:ok, %{"axes" => normalized}},
          else: {:error, :invalid_product_options}

      error ->
        error
    end
  end

  defp normalize_axes(_axes), do: {:error, :invalid_product_options}

  defp normalize_axis(axis) when is_map(axis) do
    name = axis |> field(:name) |> trim()
    values = axis |> field(:values) |> List.wrap() |> Enum.map(&trim/1) |> Enum.uniq()

    if is_binary(name) and name != "" and String.length(name) <= 40 and values != [] and
         length(values) <= @max_values and
         Enum.all?(values, &(is_binary(&1) and &1 != "" and String.length(&1) <= 40)) do
      {:ok, %{"name" => name, "values" => values}}
    else
      {:error, :invalid_product_options}
    end
  end

  defp normalize_axis(_axis), do: {:error, :invalid_product_options}

  @doc """
  Checks a variant's `option_values` (`%{axis name => value}`) against the
  product's options: one known value for every axis, nothing else.
  """
  @spec validate_option_values(map(), map()) :: {:ok, map()} | {:error, :invalid_option_values}
  def validate_option_values(options, option_values) do
    {:ok, %{"axes" => axes}} = normalize_options(options) |> fallback_options()
    values = Map.new(option_values || %{}, fn {key, value} -> {to_string(key), trim(value)} end)

    valid? =
      map_size(values) == length(axes) and
        Enum.all?(axes, fn %{"name" => name, "values" => allowed} ->
          Map.get(values, name) in allowed
        end)

    if valid?, do: {:ok, values}, else: {:error, :invalid_option_values}
  end

  defp fallback_options({:ok, _options} = ok), do: ok
  defp fallback_options(_error), do: {:ok, %{"axes" => []}}

  @doc "A variant's display title from its option values, in axis order."
  @spec variant_title(map(), map()) :: String.t() | nil
  def variant_title(options, option_values) do
    {:ok, %{"axes" => axes}} = normalize_options(options) |> fallback_options()

    case Enum.map(axes, &Map.get(option_values || %{}, &1["name"])) |> Enum.reject(&is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " / ")
    end
  end

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value
end
