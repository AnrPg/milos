defmodule Palee.Application.Ports.KeyDerivation do
  @moduledoc """
  Derives a purpose-bound secret key from the application secret (ADR-155):
  door codes, personal member codes and Wallet barcodes are HMACs under keys
  that never leave the server and that a database dump does not contain.
  `material` binds the key to one thing (a location's seed, a box).
  """

  @callback derive(purpose :: String.t(), material :: binary()) :: binary()
end
