defmodule Palee.Infrastructure.Security.PhoenixKeyDerivation do
  @moduledoc """
  Keys from the endpoint's `secret_key_base` (ADR-155): a PBKDF2 key per
  purpose (cached by Plug.Crypto), then HMAC-SHA256 over the material, so
  each location seed or box gets its own 256-bit key.
  """

  @behaviour Palee.Application.Ports.KeyDerivation

  @impl true
  def derive(purpose, material) when is_binary(purpose) and is_binary(material) do
    base = PaleeWeb.Endpoint.config(:secret_key_base)

    purpose_key =
      Plug.Crypto.KeyGenerator.generate(base, "milos:" <> purpose,
        length: 32,
        cache: Plug.Crypto.Keys
      )

    :crypto.mac(:hmac, :sha256, purpose_key, material)
  end
end
