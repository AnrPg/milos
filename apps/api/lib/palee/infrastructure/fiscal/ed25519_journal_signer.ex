defmodule Palee.Infrastructure.Fiscal.Ed25519JournalSigner do
  @moduledoc """
  Ed25519 signer of the fiscal journal (ADR-242), with OTP's `:crypto`.

  Configuration (`config :palee, #{inspect(__MODULE__)}`):

    * `signing_key` – `"<key id>:<base64 32-byte seed>"` (prod:
      `FISCAL_JOURNAL_SIGNING_KEY`); without it `sign/1` refuses;
    * `retired_public_keys` – `"<key id>:<base64 public key>,…"` of keys
      used before a rotation, so old entries keep verifying
      (`FISCAL_JOURNAL_RETIRED_PUBLIC_KEYS`).

  Generate a key: `:crypto.strong_rand_bytes(32) |> Base.encode64()`.
  """

  @behaviour Palee.Fiscal.Ports.JournalSigner

  @algorithm "Ed25519"

  @impl true
  def sign(message) when is_binary(message) do
    case active_key() do
      {:ok, key_id, private_key, _public_key} ->
        signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
        {:ok, %{signature: Base.encode64(signature), key_id: key_id}}

      :error ->
        {:error, :journal_signing_unavailable}
    end
  end

  @impl true
  def verify(message, signature, key_id) when is_binary(message) do
    with {:ok, public_key} <- public_key(key_id),
         {:ok, raw} <- Base.decode64(signature || "") do
      :crypto.verify(:eddsa, :none, message, raw, [public_key, :ed25519])
    else
      _ -> false
    end
  end

  @impl true
  def public_keys do
    active =
      case active_key() do
        {:ok, key_id, _private, public_key} -> [{key_id, public_key}]
        :error -> []
      end

    (active ++ retired_keys())
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {key_id, public_key} ->
      %{key_id: key_id, algorithm: @algorithm, public_key: Base.encode64(public_key)}
    end)
  end

  defp public_key(key_id) do
    Enum.find_value(public_keys(), :error, fn key ->
      if key.key_id == key_id, do: Base.decode64(key.public_key)
    end)
  end

  defp active_key do
    with value when is_binary(value) and value != "" <- config(:signing_key),
         [key_id, seed64] <- String.split(value, ":", parts: 2),
         {:ok, seed} when byte_size(seed) == 32 <- Base.decode64(String.trim(seed64)) do
      {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519, seed)
      {:ok, key_id, private_key, public_key}
    else
      _ -> :error
    end
  end

  defp retired_keys do
    (config(:retired_public_keys) || "")
    |> String.split(",", trim: true)
    |> Enum.flat_map(fn pair ->
      with [key_id, key64] <- String.split(String.trim(pair), ":", parts: 2),
           {:ok, key} when byte_size(key) == 32 <- Base.decode64(key64) do
        [{key_id, key}]
      else
        _ -> []
      end
    end)
  end

  defp config(key), do: :palee |> Application.get_env(__MODULE__, []) |> Keyword.get(key)
end
