defmodule Palee.Identity.Domain.EmailChangePolicy do
  @moduledoc """
  ADR-207: the pure rules of changing a login's email.

  - A change is pending for as long as its confirmation link lives (24 h,
    ADR-203's `email_change` purpose); a resend starts the clock again.
  - "This wasn't me" locks the login against new changes for 7 days.
  """

  @pending_seconds 24 * 60 * 60
  @lock_seconds 7 * 24 * 60 * 60

  @doc "When a change asked for (or resent) at `now` lapses."
  def pending_expires_at(%DateTime{} = now), do: DateTime.add(now, @pending_seconds, :second)

  @doc "Until when \"this wasn't me\" at `now` locks the login."
  def lock_until(%DateTime{} = now), do: DateTime.add(now, @lock_seconds, :second)

  @doc "Whether a lock ending at `locked_until` still holds at `now`."
  def locked?(nil, _now), do: false
  def locked?(%DateTime{} = locked_until, now), do: DateTime.compare(locked_until, now) == :gt

  @doc "Whether a pending change has lapsed."
  def expired?(%{expires_at: %DateTime{} = expires_at}, now),
    do: DateTime.compare(expires_at, now) != :gt

  @doc """
  The new address, normalised (trim, downcase), when it is one plain
  `local@domain.tld`: `{:ok, email}`, `{:error, :invalid_email}`, or
  `{:error, :email_unchanged}` for the login's own address.
  """
  def new_address(raw, current_email) when is_binary(raw) do
    email = normalize(raw)

    cond do
      not Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email) -> {:error, :invalid_email}
      String.length(email) > 254 -> {:error, :invalid_email}
      email == normalize(current_email || "") -> {:error, :email_unchanged}
      true -> {:ok, email}
    end
  end

  def new_address(_raw, _current_email), do: {:error, :invalid_email}

  @doc "Whether two addresses are the same login email (case-insensitive)."
  def same_address?(a, b) when is_binary(a) and is_binary(b),
    do: normalize(a) == normalize(b)

  def same_address?(_a, _b), do: false

  @doc "An address as logins store it: trimmed and lower case."
  def normalize(email) when is_binary(email), do: email |> String.trim() |> String.downcase()
  def normalize(_email), do: nil
end
