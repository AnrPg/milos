defmodule Palee.Notifications.Domain.PushContact do
  @moduledoc """
  The contact push services (Google, Apple, Mozilla) use to reach the Palee
  team about our alerts: the VAPID `sub` claim, a `mailto:` or `https:` URL
  (RFC 8292 §2.1). A plain email gets `mailto:` in front of it (ADR-277).
  """

  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @spec normalize(term()) :: {:ok, String.t()} | {:error, :invalid_push_contact}
  def normalize(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      String.starts_with?(value, "mailto:") and
          Regex.match?(@email, String.replace_prefix(value, "mailto:", "")) ->
        {:ok, value}

      String.starts_with?(value, "https://") and byte_size(value) > 8 ->
        {:ok, value}

      Regex.match?(@email, value) ->
        {:ok, "mailto:" <> value}

      true ->
        {:error, :invalid_push_contact}
    end
  end

  def normalize(_value), do: {:error, :invalid_push_contact}
end
