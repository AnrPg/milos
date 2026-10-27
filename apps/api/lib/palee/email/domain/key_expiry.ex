defmodule Palee.Email.Domain.KeyExpiry do
  @moduledoc """
  When the SMTP key's expiry (`SMTP_KEY_EXPIRES_ON`) needs attention
  (ADR-212): from 30 days before, every daily check warns; after it, mail
  stops (the provider refuses the key).
  """

  @warn_days 30

  @type state :: :unknown | :ok | {:expiring, non_neg_integer()} | :expired

  @doc "How many days the key has left on `today` (negative once expired)."
  @spec days_left(Date.t(), Date.t()) :: integer()
  def days_left(%Date{} = expires_on, %Date{} = today), do: Date.diff(expires_on, today)

  @doc "The key's state on `today`, from its expiry date (nil when not configured)."
  @spec state(Date.t() | nil, Date.t()) :: state()
  def state(nil, _today), do: :unknown

  def state(%Date{} = expires_on, %Date{} = today) do
    case days_left(expires_on, today) do
      days when days < 0 -> :expired
      days when days <= @warn_days -> {:expiring, days}
      _days -> :ok
    end
  end

  @doc "How many days ahead the check starts warning."
  def warn_days, do: @warn_days

  @doc "An ISO date (`2027-10-26`) from config, or nil when unset or not a date."
  @spec parse(String.t() | nil) :: Date.t() | nil
  def parse(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  def parse(_value), do: nil
end
