defmodule MilosTraining.Infrastructure.Notifications.NativePushTokenCache do
  @moduledoc """
  Keeps the providers' short-lived auth tokens between pushes (ADR-171): the
  APNs provider JWT (Apple refuses a new one more often than every 20 minutes
  and an old one after an hour) and the FCM OAuth access token (one hour).
  Entries are replaced rarely, so `:persistent_term` fits.
  """

  @doc """
  Returns the cached value under `key` while it has more than `margin` seconds
  left, otherwise calls `fun` (which answers `{:ok, value, ttl_seconds}`) and
  caches its value.
  """
  def fetch(key, margin, fun) when is_function(fun, 0) do
    now = System.system_time(:second)

    case :persistent_term.get({__MODULE__, key}, nil) do
      {value, expires_at} when expires_at - margin > now ->
        {:ok, value}

      _missing_or_stale ->
        with {:ok, value, ttl} <- fun.() do
          :persistent_term.put({__MODULE__, key}, {value, now + ttl})
          {:ok, value}
        end
    end
  end

  @doc "Drops a cached value (after the provider refused it)."
  def forget(key) do
    :persistent_term.erase({__MODULE__, key})
    :ok
  end
end
