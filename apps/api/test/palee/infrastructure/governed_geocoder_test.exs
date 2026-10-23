defmodule Palee.Infrastructure.Facility.GovernedGeocoderTest do
  @moduledoc "ADR-188: geocoder tiers, the app-wide cap and the shared cache."

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Facility.GovernedGeocoder
  alias Palee.Infrastructure.Security.MemoryRateLimiter

  defmodule Backend do
    @moduledoc false
    @behaviour Palee.Application.Ports.Geocoder

    @impl true
    def search(query, opts) do
      send(self(), {:asked, opts[:base_url], query})

      case {opts[:base_url], query} do
        {"http://own", "athens"} -> {:ok, [:own_athens]}
        {"http://own", "down"} -> {:error, :geocoder_unavailable}
        {"http://own", _query} -> {:ok, []}
        {"http://public", _query} -> {:ok, [:public_answer]}
      end
    end

    @impl true
    def reverse(_lat, _lng, opts) do
      send(self(), {:asked, opts[:base_url], :reverse})
      {:ok, if(opts[:base_url] == "http://public", do: :public_place)}
    end
  end

  setup do
    previous = Application.get_env(:palee, :geocoder_governor)

    Application.put_env(:palee, :geocoder_governor,
      backend: Backend,
      tiers: [
        [base_url: "http://own", max_per_minute: nil],
        [base_url: "http://public", max_per_minute: 2]
      ]
    )

    MemoryRateLimiter.reset!()
    on_exit(fn -> Application.put_env(:palee, :geocoder_governor, previous) end)
  end

  # Unique per run: a Redis in CI keeps answers between runs.
  defp fresh(word), do: "#{word} #{System.unique_integer([:positive])}"

  test "our own Photon answers first; the public one only when ours has nothing" do
    assert {:ok, [:own_athens]} = GovernedGeocoder.search("athens", limit: 5)
    refute_received {:asked, "http://public", _query}

    lima = fresh("lima")
    assert {:ok, [:public_answer]} = GovernedGeocoder.search(lima, limit: 5)
    assert_received {:asked, "http://own", ^lima}
    assert_received {:asked, "http://public", ^lima}

    assert {:ok, :public_place} = GovernedGeocoder.reverse(:rand.uniform(), 2.0, [])
  end

  test "an outage of our own Photon falls through to the public one" do
    assert {:ok, [:public_answer]} = GovernedGeocoder.search("down", limit: :rand.uniform(1000))
  end

  test "the public tier is capped app-wide; over it, ours still answers" do
    assert {:ok, [:public_answer]} = GovernedGeocoder.search(fresh("one"), [])
    assert {:ok, [:public_answer]} = GovernedGeocoder.search(fresh("two"), [])
    # Third public call this minute: skipped, and ours had nothing.
    assert {:ok, []} = GovernedGeocoder.search(fresh("three"), [])
    assert {:ok, [:own_athens]} = GovernedGeocoder.search("athens", [])
  end
end
