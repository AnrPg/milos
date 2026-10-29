defmodule Palee.Fiscal.Ports.JournalSigner do
  @moduledoc """
  Signs fiscal journal hashes and archive manifests (ADR-242). The adapter
  holds the private key; the public keys are published in every archive so
  anyone can verify without Palee.
  """

  @type signature :: %{signature: String.t(), key_id: String.t()}

  @doc "Signs `message`: `{:ok, %{signature (base64), key_id}}` or `{:error, :journal_signing_unavailable}`."
  @callback sign(binary()) :: {:ok, signature()} | {:error, :journal_signing_unavailable}

  @doc "True when `signature` (base64) is a valid signature of `message` by `key_id`."
  @callback verify(binary(), String.t(), String.t()) :: boolean()

  @doc "Public keys (current and retired): `[%{key_id, algorithm, public_key (base64)}]`."
  @callback public_keys() :: [%{key_id: String.t(), algorithm: String.t(), public_key: String.t()}]
end
