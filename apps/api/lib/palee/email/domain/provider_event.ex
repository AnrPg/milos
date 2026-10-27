defmodule Palee.Email.Domain.ProviderEvent do
  @moduledoc """
  What a mail provider's webhook says about a sent email (ADR-212), as pure
  decisions. Brevo's transactional webhook posts one JSON object per event
  (or, batched, a list of them):

      {"event": "hard_bounce", "email": "jo@example.com", "id": 1234,
       "message-id": "<...@palee.app>", "ts_event": 1767225600,
       "ts_epoch": 1767225600123, "reason": "550 5.1.1 user unknown", ...}

  `parse_brevo/1` reads them into events; `action/1` says what each one
  does:

  | event | action |
  |---|---|
  | `hard_bounce`, `invalid_email`, `blocked` | suppress the address (`bounce`), message `bounced` |
  | `spam` (a complaint) | suppress the address (`complaint`), message `complained` |
  | `unsubscribed` | opt the address out of that transactional kind |
  | `delivered` | set the message's `delivered_at` |
  | `soft_bounce`, `deferred`, `error` | record only (the provider retries) |
  | anything else (opens, clicks, `request`) | ignored |

  Every event has a `digest` over its identifying fields, so the same event
  posted twice is applied once.
  """

  @type name ::
          :hard_bounce
          | :soft_bounce
          | :invalid_email
          | :blocked
          | :spam
          | :unsubscribed
          | :delivered
          | :deferred
          | :error

  @type t :: %{
          event: name(),
          address: String.t() | nil,
          message_id: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          reason: String.t() | nil,
          digest: binary()
        }

  @type action ::
          {:suppress, :bounce | :complaint, status :: String.t()}
          | :opt_out
          | :delivered
          | :record

  @events %{
    "hard_bounce" => :hard_bounce,
    "soft_bounce" => :soft_bounce,
    "invalid_email" => :invalid_email,
    "blocked" => :blocked,
    "spam" => :spam,
    "complaint" => :spam,
    "unsubscribed" => :unsubscribed,
    "delivered" => :delivered,
    "deferred" => :deferred,
    "error" => :error
  }

  @max_reason 500
  @max_batch 500

  @doc "The event names Palee acts on or records, as Brevo spells them."
  def known_events, do: @events |> Map.keys() |> Enum.reject(&(&1 == "complaint")) |> Enum.sort()

  @doc """
  The events of one Brevo webhook body: `{:ok, events}` (events Palee does
  not act on are left out, so the list may be empty), or
  `{:error, :invalid_payload}` when the body is not an event or a list of
  them.
  """
  @spec parse_brevo(term()) :: {:ok, [t()]} | {:error, :invalid_payload}
  def parse_brevo(%{"event" => _event} = payload), do: parse_brevo([payload])

  def parse_brevo(%{"_json" => list}) when is_list(list), do: parse_brevo(list)

  def parse_brevo(list) when is_list(list) and list != [] and length(list) <= @max_batch do
    if Enum.all?(list, &(is_map(&1) and is_binary(&1["event"]))),
      do: {:ok, list |> Enum.map(&parse_one/1) |> Enum.reject(&is_nil/1)},
      else: {:error, :invalid_payload}
  end

  def parse_brevo(_payload), do: {:error, :invalid_payload}

  defp parse_one(payload) do
    case Map.fetch(@events, String.downcase(payload["event"])) do
      {:ok, event} ->
        address = address(payload["email"])
        message_id = message_id(payload["message-id"] || payload["message_id"])
        occurred_at = occurred_at(payload)

        %{
          event: event,
          address: address,
          message_id: message_id,
          occurred_at: occurred_at,
          reason: reason(payload["reason"]),
          digest: digest([event, address, message_id, payload["ts_epoch"], payload["ts_event"]])
        }

      :error ->
        nil
    end
  end

  @doc "What `event` does (see the moduledoc's table)."
  @spec action(t() | name()) :: action()
  def action(%{event: event}), do: action(event)

  def action(event) when event in [:hard_bounce, :invalid_email, :blocked],
    do: {:suppress, :bounce, "bounced"}

  def action(:spam), do: {:suppress, :complaint, "complained"}
  def action(:unsubscribed), do: :opt_out
  def action(:delivered), do: :delivered
  def action(_recorded), do: :record

  @doc """
  The Message-ID as the outbox stores it (`<id@domain>`): providers report
  it with or without the angle brackets.
  """
  def message_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      "<" <> _rest = id -> id
      id -> "<" <> id <> ">"
    end
  end

  def message_id(_value), do: nil

  defp address(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "" -> nil
      address -> address
    end
  end

  defp address(_value), do: nil

  defp occurred_at(%{"ts_epoch" => ms}) when is_integer(ms),
    do: DateTime.from_unix!(ms, :millisecond) |> DateTime.add(0, :microsecond)

  defp occurred_at(%{"ts_event" => seconds}) when is_integer(seconds),
    do: DateTime.from_unix!(seconds) |> DateTime.add(0, :microsecond)

  defp occurred_at(%{"ts_event" => seconds}) when is_binary(seconds) do
    case Integer.parse(seconds) do
      {value, ""} -> occurred_at(%{"ts_event" => value})
      _other -> nil
    end
  end

  defp occurred_at(_payload), do: nil

  defp reason(value) when is_binary(value) and value != "",
    do: value |> String.replace(~r/[\r\n]+/, " ") |> String.slice(0, @max_reason)

  defp reason(_value), do: nil

  defp digest(parts),
    do: :crypto.hash(:sha256, Enum.map_join(parts, "|", &to_string(&1 || "")))
end
