defmodule Palee.Infrastructure.Wallet.HttpImageSource do
  @moduledoc """
  Fetches a box's public logo for its Apple pass (ADR-155): PNG only, at
  most 512 KB, a few seconds at most; anything else and the pass uses a
  tile in the box's colour.
  """

  @behaviour Palee.Wallet.Ports.ImageSource

  @max_bytes 512 * 1024

  @impl true
  def fetch(url) when is_binary(url) do
    case Req.get(url, retry: false, receive_timeout: 3_000, decode_body: false) do
      {:ok, %{status: 200, body: <<137, 80, 78, 71, _rest::binary>> = body}}
      when byte_size(body) <= @max_bytes ->
        {:ok, body}

      {:ok, _other} ->
        {:error, :unusable_logo}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
