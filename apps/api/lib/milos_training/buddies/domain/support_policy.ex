defmodule MilosTraining.Buddies.Domain.SupportPolicy do
  @moduledoc """
  «Χρειάζομαι στήριξη» (ADR-160 §2, board 15 Q3–Q5, Q7). One tap sends an
  optional one-line message to every active buddy; nothing about a craving
  goes with it. The member can take it back for five seconds, after which
  buddies are told. A few requests an hour at most, so it never becomes
  spam. A buddy answers with a quick reply or their own words; if nobody
  has answered after ten minutes, the sender gets a calm card with small
  things to do, «Στείλε ξανά» and a help-lines link marked as information,
  never advice.
  """

  @message_max 280
  @sources ~w(craving quick)
  @undo_seconds 5
  @rate_limit 3
  @rate_window_seconds 3_600
  @nudge_minutes 10
  @reply_kinds ~w(here walk call text)
  @quick_replies ~w(here walk call)
  @reply_text_max 500
  @suggestions ~w(breathing water walk)
  @breathing_seconds 120

  def message_max, do: @message_max
  def sources, do: @sources
  def undo_seconds, do: @undo_seconds
  def rate_limit, do: @rate_limit
  def rate_window_seconds, do: @rate_window_seconds
  def nudge_minutes, do: @nudge_minutes
  def reply_kinds, do: @reply_kinds
  def quick_replies, do: @quick_replies
  def reply_text_max, do: @reply_text_max
  def suggestions, do: @suggestions
  def breathing_seconds, do: @breathing_seconds

  @doc "The optional message: trimmed, blank as none, at most #{@message_max} characters."
  def normalize_message(nil), do: {:ok, nil}

  def normalize_message(message) when is_binary(message) do
    case String.trim(message) do
      "" ->
        {:ok, nil}

      text ->
        if String.length(text) <= @message_max, do: {:ok, text}, else: {:error, :message_too_long}
    end
  end

  def normalize_message(_message), do: {:error, :invalid_message}

  def normalize_source(source) when is_atom(source) and not is_nil(source),
    do: normalize_source(Atom.to_string(source))

  def normalize_source(nil), do: {:ok, "quick"}
  def normalize_source(source) when source in @sources, do: {:ok, source}
  def normalize_source(_source), do: {:error, :invalid_support_source}

  @doc "Where rate limiting starts counting, for a request at `now`."
  def rate_window_start(%DateTime{} = now), do: DateTime.add(now, -@rate_window_seconds, :second)

  @doc "Whether one more request fits, given how many were sent in the window."
  def check_rate(sent_in_window) when sent_in_window < @rate_limit, do: :ok
  def check_rate(_sent_in_window), do: {:error, :support_rate_limited}

  def check_buddies([]), do: {:error, :no_active_buddies}
  def check_buddies(_buddies), do: :ok

  @doc "Until when the sender can take a request back."
  def undo_until(%{inserted_at: at}), do: DateTime.add(at, @undo_seconds, :second)

  @doc "When buddies are told (the end of the undo window)."
  def deliver_at(request), do: undo_until(request)

  @doc "When the no-reply card is due."
  def nudge_at(%{inserted_at: at}), do: DateTime.add(at, @nudge_minutes * 60, :second)

  def can_undo?(%{undone_at: at}, _now) when not is_nil(at), do: {:error, :already_undone}
  def can_undo?(%{delivered_at: at}, _now) when not is_nil(at), do: {:error, :undo_window_passed}

  def can_undo?(request, %DateTime{} = now) do
    if DateTime.compare(now, undo_until(request)) == :gt,
      do: {:error, :undo_window_passed},
      else: :ok
  end

  @doc "Whether buddies should be told now (not taken back, not yet told)."
  def deliverable?(%{undone_at: nil, delivered_at: nil}), do: true
  def deliverable?(_request), do: false

  @doc """
  The sender's no-reply card at `now`: due once ten minutes passed with no
  reply on a request that was sent; gone as soon as anyone answers.
  """
  def nudge(request, replies, %DateTime{} = now) do
    due? =
      is_nil(request.undone_at) and replies == [] and
        DateTime.compare(now, nudge_at(request)) != :lt

    %{
      due: due?,
      due_at: nudge_at(request),
      sent_at: request.nudge_sent_at,
      suggestions: @suggestions,
      breathing_seconds: @breathing_seconds,
      can_resend: due?,
      help_lines: %{path: "/help/support-lines", informational: true}
    }
  end

  @doc "Whether the job should send the card (idempotent: once, only while due)."
  def nudge_needed?(request, replies, now),
    do:
      is_nil(request.nudge_sent_at) and not is_nil(request.delivered_at) and
        nudge(request, replies, now).due

  @doc "A buddy's reply: a known kind and optional words (required for `text`)."
  def validate_reply(kind, text) do
    with {:ok, kind} <- reply_kind(kind),
         {:ok, text} <- reply_text(text) do
      if kind == "text" and is_nil(text),
        do: {:error, :reply_text_required},
        else: {:ok, kind, text}
    end
  end

  defp reply_kind(kind) when kind in @reply_kinds, do: {:ok, kind}
  defp reply_kind(_kind), do: {:error, :invalid_reply_kind}

  defp reply_text(nil), do: {:ok, nil}

  defp reply_text(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:ok, nil}

      text ->
        if String.length(text) <= @reply_text_max,
          do: {:ok, text},
          else: {:error, :reply_too_long}
    end
  end

  defp reply_text(_text), do: {:error, :invalid_reply_text}

  @doc "Whether a buddy may answer this request."
  def can_reply?(%{undone_at: at}) when not is_nil(at), do: {:error, :not_found}
  def can_reply?(%{delivered_at: nil}), do: {:error, :not_found}
  def can_reply?(_request), do: :ok

  @doc "A reply of kind `call` carries the sender's phone, only when they share it."
  def phone_for(kind, phone) when kind == "call" and is_binary(phone), do: phone
  def phone_for(_kind, _phone), do: nil
end
