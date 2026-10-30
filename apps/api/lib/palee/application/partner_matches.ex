defmodule Palee.Application.PartnerMatches do
  @moduledoc """
  A person's Partners matches and their conversations (ADR-169 §4, §7;
  account-level since ADR-280): the list for Μηνύματα › Partners, ending a
  match, messages, read marks, and posting a «Κλείστε μαζί» plan (the
  suggestions side picks what; `post_plan/3` writes it).

  A conversation takes messages only while its match is active; otherwise
  it reads as read-only. Each message tells the other person once
  (`partner_message`, who wrote, never what).
  """

  alias Palee.Application.{CommunityPeople, PartnerRealtime}
  alias Palee.{Notifications, Partners}

  @doc "Every match of the viewer, active first, latest conversation first."
  def list(%{user_id: user_id} = context) do
    matches = Partners.list_matches(context, user_id)
    unread = Partners.unread_counts(context, user_id, matches)
    people = CommunityPeople.by_ids(Enum.map(matches, &Partners.other_party(&1, user_id)))

    rows =
      matches
      |> Enum.map(&present(&1, user_id, people, Map.get(unread, &1.id, 0)))
      |> Enum.sort_by(&{&1.status != "active", -DateTime.to_unix(sort_time(&1), :microsecond)})

    {:ok, %{matches: rows}}
  end

  @doc "One match as the swipe that made it shows it."
  def present_summary(%{user_id: user_id}, match) do
    people = CommunityPeople.by_ids([Partners.other_party(match, user_id)])
    present(match, user_id, people, 0)
  end

  @doc """
  The viewer's own match (the seam the suggestions side calls): the match
  and the other person's id, or `{:error, :not_found}`.
  """
  def own_match(%{user_id: user_id} = context, match_id) do
    with {:ok, match} <- locate(context, match_id),
         do: {:ok, match, Partners.other_party(match, user_id)}
  end

  @doc "Ends a match quietly; its conversation stays readable, read-only."
  def end_match(%{user_id: user_id} = context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, match} <- locate(context, match_id),
         {:ok, changes} <- Partners.end_changes(match, "unmatched", user_id, now),
         {:ok, match} <- Partners.update_match(context, match, changes) do
      PartnerRealtime.match_changed(match)
      {:ok, %{id: match.id, status: match.status}}
    end
  end

  @doc "A page of the conversation, newest first, with the next (older) cursor."
  def messages(%{user_id: user_id} = context, match_id, params) do
    limit = Partners.message_page_limit(param(params, "limit"))

    with {:ok, match} <- locate(context, match_id),
         {:ok, cursor} <- Partners.decode_message_cursor(param(params, "cursor")) do
      rows = Partners.list_messages(context, match.id, cursor, limit + 1)
      {page, next_cursor} = Partners.message_page(rows, limit)
      people = people(match)

      {:ok,
       %{
         messages: Enum.map(page, &present_message(&1, user_id, people)),
         next_cursor: next_cursor,
         read_only: Partners.read_only?(match),
         unread: Map.get(Partners.unread_counts(context, user_id, [match]), match.id, 0)
       }}
    end
  end

  @doc "Writes a message into an active match and tells the other person once."
  def post(%{user_id: user_id} = context, match_id, params, now \\ DateTime.utc_now()) do
    with {:ok, match} <- locate(context, match_id),
         :ok <- Partners.can_message?(match),
         {:ok, body} <- Partners.normalize_message_body(param(params, "body")),
         {:ok, message} <-
           Partners.insert_message(
             context,
             %{match_id: match.id, author_id: user_id, kind: "text", body: body},
             now
           ) do
      delivered(context, match, message)
      {:ok, present_message(message, user_id, people(match))}
    end
  end

  @doc """
  Posts a «Κλείστε μαζί» plan into an active match (the seam the suggestions
  side calls): `plan` is `%{kind: "class" | "event" | "trial", id:, title:,
  starts_at:, place:}`, kept as a snapshot. An optional `:body` is a note.
  """
  def post_plan(%{user_id: user_id} = context, match_id, plan, now \\ DateTime.utc_now()) do
    with {:ok, match} <- locate(context, match_id),
         :ok <- Partners.can_message?(match),
         {:ok, snapshot} <- Partners.plan_snapshot(plan),
         {:ok, note} <- Partners.normalize_note(param(plan, "body")),
         {:ok, message} <-
           Partners.insert_message(
             context,
             %{match_id: match.id, author_id: user_id, kind: "plan", body: note, plan: snapshot},
             now
           ) do
      delivered(context, match, message)
      {:ok, present_message(message, user_id, people(match))}
    end
  end

  @doc "Marks the conversation read up to now for the viewer."
  def mark_read(%{user_id: user_id} = context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, match} <- locate(context, match_id) do
      unread = Map.get(Partners.unread_counts(context, user_id, [match]), match.id, 0)

      if unread > 0 do
        {:ok, match} =
          Partners.update_match(context, match, %{Partners.read_field(match, user_id) => now})

        PartnerRealtime.messages_read(match)
      end

      {:ok, %{read: unread}}
    end
  end

  @doc "Ends the active match between the viewer and another person (a block or a report)."
  def end_between(%{user_id: user_id} = context, other_id, reason, now \\ DateTime.utc_now()) do
    context
    |> Partners.end_matches(%{pair: {user_id, other_id}}, %{
      status: "ended",
      end_reason: reason,
      ended_by_id: user_id,
      ended_at: now
    })
    |> Enum.each(&PartnerRealtime.match_changed/1)

    :ok
  end

  # ------------------------------------------------------------- internals

  defp locate(%{user_id: user_id} = context, match_id) do
    case Partners.get_match(context, match_id) do
      %{} = match ->
        if Partners.match_party?(match, user_id), do: {:ok, match}, else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp delivered(%{user_id: user_id} = context, match, message) do
    PartnerRealtime.message_created(match)

    Notifications.dispatch_event(:partner_message, %{
      user_id: Partners.other_party(match, user_id),
      match_id: match.id,
      message_id: message.id,
      author_id: user_id,
      author_nickname: nickname(context),
      dedupe_key: "partner_message:#{message.id}"
    })
  end

  defp nickname(%{account: %{} = account}),
    do: Map.get(account, :display_nickname) || Map.get(account, :nickname)

  defp nickname(%{user_id: user_id}),
    do: CommunityPeople.by_ids([user_id]) |> CommunityPeople.person(user_id) |> Map.get(:nickname)

  defp people(match), do: CommunityPeople.by_ids([match.user_a_id, match.user_b_id])

  defp present(match, user_id, people, unread) do
    other_id = Partners.other_party(match, user_id)

    %{
      id: match.id,
      person: CommunityPeople.person(people, other_id),
      partner_id: other_id,
      status: match.status,
      end_reason: match.end_reason,
      ended_by_me: match.ended_by_id == user_id,
      read_only: Partners.read_only?(match),
      unread: unread,
      matched_at: match.matched_at,
      last_message_at: match.last_message_at
    }
  end

  defp sort_time(row), do: row.last_message_at || row.matched_at

  defp present_message(message, user_id, people) do
    %{
      id: message.id,
      match_id: message.match_id,
      kind: message.kind,
      body: message.body,
      plan: present_plan(message.plan),
      mine: message.author_id == user_id,
      author: CommunityPeople.person(people, message.author_id),
      created_at: message.inserted_at
    }
  end

  defp present_plan(nil), do: nil

  defp present_plan(plan) do
    %{
      kind: plan["kind"],
      id: plan["id"],
      title: plan["title"],
      starts_at: plan["starts_at"],
      place: plan["place"]
    }
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end
