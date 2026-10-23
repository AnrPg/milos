defmodule Palee.Finance.Domain.TransactionFeed do
  @moduledoc """
  Εγώ › Πληρωμές › Συναλλαγές as a pure feed: entry shape, newest-first
  order, provider scope, kind filter and cursor pages.

  An entry is `id` (`kind:source_id`, stable across pages), `kind`,
  `source_id`, `counterparty`, `title`, `amount_cents` (negative for money
  back), `currency`, `status`, `date`, `details` and `source_url` (the
  source's own page, when it has one). The cursor is the opaque, URL-safe
  sort key of the last entry on a page; ties on the same instant break on
  `id`, so pages never repeat or skip an entry.

  `shop_order` is reserved for shop purchases (post-MVP, TD-189).
  """

  @kinds ~w(invoice payment refund credit event_payment event_refund shop_order)
  @event_kinds ~w(event_payment event_refund)
  @default_limit 30
  @max_limit 100

  def kinds, do: @kinds

  @doc "Builds one entry. `at` may be a date, a naive or a UTC datetime, or nil."
  def entry(
        kind,
        source_id,
        party,
        title,
        amount_cents,
        currency,
        status,
        at,
        details,
        opts \\ []
      )
      when kind in @kinds do
    date = to_datetime(at)
    id = "#{kind}:#{source_id}"

    %{
      id: id,
      kind: kind,
      source_id: source_id,
      counterparty: party,
      title: title,
      amount_cents: amount_cents,
      currency: currency || "EUR",
      status: status && to_string(status),
      date: date,
      details: details,
      source_url: Keyword.get(opts, :source_url),
      sort: sort_key(date, id)
    }
  end

  @doc """
  One page of `entries`, newest first. `scope` keeps one provider's entries
  plus the event entries of hosts that are not providers (`provider_ids`),
  so a paid event is never missing; `kind` narrows after `total` and
  `kinds` are counted.
  """
  def page(entries, %{
        scope: scope,
        provider_ids: provider_ids,
        kind: kind,
        cursor: cursor,
        limit: limit
      }) do
    scoped =
      entries
      |> Enum.filter(&in_scope?(&1, scope, provider_ids))
      |> Enum.sort_by(& &1.sort, :desc)

    present = scoped |> Enum.map(& &1.kind) |> MapSet.new()
    filtered = if kind, do: Enum.filter(scoped, &(&1.kind == kind)), else: scoped

    {items, more} =
      filtered
      |> Enum.drop_while(&(cursor && &1.sort >= cursor))
      |> Enum.take(limit + 1)
      |> Enum.split(limit)

    %{
      transactions: Enum.map(items, &Map.delete(&1, :sort)),
      next_cursor: if(more != [], do: encode_cursor(List.last(items).sort)),
      total: length(scoped),
      kinds: Enum.filter(@kinds, &MapSet.member?(present, &1))
    }
  end

  defp in_scope?(_entry, scope, _provider_ids) when scope in [nil, ""], do: true

  defp in_scope?(entry, organization_id, provider_ids) do
    entry.counterparty.organization_id == organization_id or
      (entry.kind in @event_kinds and
         not MapSet.member?(provider_ids, entry.counterparty.organization_id))
  end

  # ── request params ──────────────────────────────────────────────────────

  @doc "Decodes a cursor from the client; nil or empty is the first page."
  def decode_cursor(cursor) when cursor in [nil, ""], do: {:ok, nil}

  def decode_cursor(cursor) when is_binary(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, key} -> if String.contains?(key, "|"), do: {:ok, key}, else: {:error, :invalid_cursor}
      :error -> {:error, :invalid_cursor}
    end
  end

  def decode_cursor(_cursor), do: {:error, :invalid_cursor}

  @doc "Validates the kind filter; nil or empty means every kind."
  def kind_filter(kind) when kind in [nil, ""], do: {:ok, nil}
  def kind_filter(kind) when kind in @kinds, do: {:ok, kind}
  def kind_filter(_kind), do: {:error, :invalid_kind}

  @doc "Page size, clamped to 1..#{@max_limit}; #{@default_limit} when missing or unreadable."
  def limit(nil), do: @default_limit
  def limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  def limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> limit(number)
      _other -> @default_limit
    end
  end

  def limit(_value), do: @default_limit

  # ── order ───────────────────────────────────────────────────────────────

  defp sort_key(nil, id), do: "0000000000000000000|" <> id

  defp sort_key(%DateTime{} = date, id) do
    unix = date |> DateTime.to_unix(:microsecond) |> max(0)
    (unix |> Integer.to_string() |> String.pad_leading(19, "0")) <> "|" <> id
  end

  defp encode_cursor(key), do: Base.url_encode64(key, padding: false)

  defp to_datetime(nil), do: nil
  defp to_datetime(%DateTime{} = at), do: at
  defp to_datetime(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp to_datetime(%Date{} = day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")
end
