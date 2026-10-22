defmodule PaleeWeb.Plugs.ForceSslExceptHealthTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias PaleeWeb.Plugs.ForceSslExceptHealth

  setup do
    previous = Application.get_env(:palee, :force_ssl)
    Application.put_env(:palee, :force_ssl, rewrite_on: [:x_forwarded_proto])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :force_ssl, previous),
        else: Application.delete_env(:palee, :force_ssl)
    end)
  end

  defp call(path, remote_ip) do
    conn(:get, "http://milos-api" <> path)
    |> Map.put(:remote_ip, remote_ip)
    |> ForceSslExceptHealth.call(ForceSslExceptHealth.init([]))
  end

  test "lets cluster-internal health probes and slug-alias lookups through over http" do
    refute call("/api/health", {10, 244, 1, 176}).halted
    refute call("/api/organization-slug-aliases/milos-method", {10, 244, 1, 176}).halted
  end

  test "redirects the same paths from outside the cluster" do
    assert call("/api/health", {203, 0, 113, 9}).status == 301
    assert call("/api/organization-slug-aliases/milos-method", {203, 0, 113, 9}).status == 301
  end

  test "redirects every other internal http request" do
    assert call("/api/memberships", {10, 244, 1, 176}).status == 301
  end
end
