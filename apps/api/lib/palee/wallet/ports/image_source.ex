defmodule Palee.Wallet.Ports.ImageSource do
  @moduledoc "Fetches a box's logo for its Apple pass (ADR-155): PNG bytes or an error."

  @callback fetch(url :: String.t()) :: {:ok, binary()} | {:error, term()}
end
