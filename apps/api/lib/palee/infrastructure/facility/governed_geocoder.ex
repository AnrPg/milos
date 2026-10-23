defmodule Palee.Infrastructure.Facility.GovernedGeocoder do
  @moduledoc """
  Wraps the real geocoder (ADR-188) so the app is fast and a polite client:

  - **Tiers.** Backends are asked in order until one has an answer: our own
    Photon (a few countries, uncapped), then the public one for the rest of
    the world. An empty answer or an outage moves on to the next tier.
  - **Cache.** Answers are kept in Redis for a day, shared by every pod, so
    one person's search serves the next.
  - **App-wide cap.** A backend with `max_per_minute` is called at most that
    often across all pods; over it the tier is skipped at once and area
    search shows stored places only.

  Without Redis it caches nothing and does not cap.
  """

  @behaviour Palee.Application.Ports.Geocoder

  alias Palee.Infrastructure.Security.RateLimiter

  require Logger

  @impl true
  def search(query, opts) do
    request = {:search, query |> String.trim() |> String.downcase(), Enum.sort(opts)}
    tiered(request, &backend().search(query, &1 ++ opts), &(&1 == []))
  end

  @impl true
  def reverse(latitude, longitude, opts) do
    request =
      {:reverse, Float.round(latitude * 1.0, 5), Float.round(longitude * 1.0, 5), Enum.sort(opts)}

    tiered(request, &backend().reverse(latitude, longitude, &1 ++ opts), &is_nil/1)
  end

  # The first tier with an answer wins; all empty is an empty answer; all
  # failing is an outage.
  defp tiered(request, call, empty?) do
    Enum.reduce_while(tiers(), {:error, :geocoder_unavailable}, fn tier, outcome ->
      case governed(tier, request, fn -> call.(base_url: tier[:base_url]) end) do
        {:ok, answer} = found ->
          if empty?.(answer), do: {:cont, found}, else: {:halt, found}

        {:error, _reason} ->
          {:cont, outcome}
      end
    end)
  end

  defp governed(tier, request, call) do
    key = cache_key(tier, request)

    case cached(key) do
      {:ok, answer} ->
        {:ok, answer}

      :miss ->
        with :ok <- allowed(tier),
             {:ok, answer} <- call.() do
          remember(key, answer)
          {:ok, answer}
        end
    end
  end

  defp cache_key(tier, request) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary({tier[:base_url], request}))
    "geocode:v1:" <> Base.url_encode64(digest, padding: false)
  end

  defp allowed(tier) do
    case tier[:max_per_minute] do
      max when is_integer(max) and max > 0 ->
        case RateLimiter.check_rate("geocoder:" <> to_string(tier[:base_url]), 60_000, max) do
          {:ok, _count} ->
            :ok

          {:error, count} when is_integer(count) ->
            Logger.info("geocoder: app-wide cap of #{max}/min reached for #{tier[:base_url]}")
            {:error, :geocoder_unavailable}

          # The limiter itself is down: let the call through.
          {:error, _reason} ->
            :ok
        end

      _uncapped ->
        :ok
    end
  end

  defp cached(key) do
    with {:ok, redix} <- redix(),
         {:ok, binary} when is_binary(binary) <- Redix.command(redix, ["GET", key]) do
      {:ok, :erlang.binary_to_term(binary, [:safe])}
    else
      _miss -> :miss
    end
  rescue
    ArgumentError -> :miss
  end

  defp remember(key, answer) do
    with {:ok, redix} <- redix() do
      ttl = Keyword.get(config(), :cache_ttl_s, 86_400)

      Redix.command(redix, [
        "SET",
        key,
        :erlang.term_to_binary(answer),
        "EX",
        Integer.to_string(ttl)
      ])
    end

    :ok
  end

  defp redix do
    case Process.whereis(:redix) do
      nil -> :error
      pid -> {:ok, pid}
    end
  end

  defp tiers, do: Keyword.get(config(), :tiers, [[base_url: nil, max_per_minute: nil]])
  defp backend, do: Keyword.fetch!(config(), :backend)
  defp config, do: Application.get_env(:palee, :geocoder_governor, [])
end
