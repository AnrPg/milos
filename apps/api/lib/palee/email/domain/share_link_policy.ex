defmodule Palee.Email.Domain.ShareLinkPolicy do
  @moduledoc """
  ADR-210: the pure rules of "Send by email" for a share link (a guest
  pass, a check-in buddy invite link, a «Φέρε φίλο» link).

    * A sender sends at most `daily_limit/0` share emails in a rolling 24 h,
      whatever their status (a typo'd address still counts).
    * The email shows the sender's display name only when it cannot pass
      for a link or an address; otherwise their @handle.
    * One email per sender, link and recipient: the idempotency key names
      all three (the link and the address only as a digest).
  """

  @daily_limit 10
  @window_seconds 24 * 60 * 60
  @name_length 60
  @kinds ~w(guest_pass buddy_invite referral)a

  @doc "The kinds of link that can be emailed."
  def kinds, do: @kinds

  @doc "The kind atom of a requested kind (a string from the request), or `:error`."
  def kind(kind) when kind in @kinds, do: {:ok, kind}

  def kind(kind) when is_binary(kind) do
    case Enum.find(@kinds, &(Atom.to_string(&1) == kind)) do
      nil -> :error
      known -> {:ok, known}
    end
  end

  def kind(_kind), do: :error

  @doc "How many share emails one sender may send a day."
  def daily_limit, do: @daily_limit

  @doc "The idempotency key prefix of one sender's share emails."
  def sender_prefix(sender_id), do: "share_link:#{sender_id}:"

  @doc "The idempotency key of `kind`'s link `ref` sent by `sender_id` to `address`."
  def key(sender_id, kind, ref, address) do
    digest =
      :crypto.hash(:sha256, [Atom.to_string(kind), 0, ref, 0, address])
      |> Base.url_encode64(padding: false)
      |> binary_part(0, 22)

    sender_prefix(sender_id) <> "#{kind}:#{digest}"
  end

  @doc """
  Whether a sender whose earlier share emails are `summaries` (with
  `inserted_at`) may send another at `now`.
  """
  def within_limit?(summaries, now) do
    since = DateTime.add(now, -@window_seconds, :second)

    recent =
      Enum.count(summaries, fn %{inserted_at: inserted_at} ->
        DateTime.compare(to_utc(inserted_at), since) == :gt
      end)

    recent < @daily_limit
  end

  @doc "The name the email shows for the sender: a plain display name, else `@handle`."
  def sender_name(display_name, handle) do
    name = clean(display_name)

    cond do
      name != "" and not link_like?(name) -> name
      is_binary(handle) and handle != "" -> "@" <> handle
      true -> name
    end
  end

  defp clean(name) when is_binary(name) do
    name
    |> String.replace(~r/\s+/u, " ")
    |> String.replace(~r/[\p{C}]/u, "")
    |> String.trim()
    |> String.slice(0, @name_length)
  end

  defp clean(_name), do: ""

  # A name that reads as an address or a link would turn the email into an
  # advert for it.
  defp link_like?(name),
    do: Regex.match?(~r/(:\/\/|www\.|@|\.[a-z]{2,}(\/|\b))/iu, name)

  defp to_utc(%DateTime{} = at), do: at
  defp to_utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
