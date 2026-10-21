defmodule MilosTraining.Application.PartnerMatches do
  @moduledoc """
  A member's Partners matches and their conversations (ADR-169 §4, §7, §8):
  the list for Μηνύματα › Partners, ending a match, messages and read
  marks, and «Κλείστε μαζί» (the gym's classes that suit both, and posting
  one as a plan).

  A match is found through the gyms of the viewer's clubs (its rows are the
  gym's). Its conversation takes messages only while the match is active
  and both people are still members of the club; otherwise it reads as
  read-only. Each message tells the other person once (`partner_message`,
  who wrote, never what).
  """

  alias MilosTraining.Application.{ClubScope, CommunityPeople, PartnerRealtime}
  alias MilosTraining.{Notifications, Organizations, Partners, Scheduling}
  alias MilosTraining.Application.Partners, as: PartnerClubs

  @doc "Every match of the viewer in the gyms of their clubs, latest conversation first."
  def list(%{user_id: user_id} = context) do
    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, scopes} <- PartnerClubs.scopes(context) do
      rows =
        Enum.flat_map(scopes, fn scope ->
          matches = Partners.list_matches(scope, user_id)
          unread = Partners.unread_counts(scope, user_id, matches)
          Enum.map(matches, &{&1, scope, Map.get(unread, &1.id, 0)})
        end)

      people =
        CommunityPeople.by_ids(
          Enum.map(rows, fn {match, _scope, _unread} -> Partners.other_party(match, user_id) end)
        )

      members = member_cache(rows, clubs)

      matches =
        rows
        |> Enum.map(fn {match, _scope, unread} ->
          club = Enum.find(clubs, &(&1.id == match.club_id))
          present(match, club, user_id, people, unread, both_members?(members, club, match))
        end)
        |> Enum.sort_by(&{&1.status != "active", -DateTime.to_unix(sort_time(&1), :microsecond)})

      {:ok, %{matches: matches}}
    end
  end

  @doc "One match as the swipe that made it shows it."
  def present_summary(%{user_id: user_id}, club, match) do
    people = CommunityPeople.by_ids([Partners.other_party(match, user_id)])
    present(match, club, user_id, people, 0, true)
  end

  @doc "Ends a match quietly; its conversation stays readable, read-only."
  def end_match(%{user_id: user_id} = context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, match, scope, _club} <- locate(context, match_id),
         {:ok, changes} <- Partners.end_changes(match, "unmatched", user_id, now),
         {:ok, match} <- Partners.update_match(scope, match, changes) do
      PartnerRealtime.match_changed(match)
      {:ok, %{id: match.id, status: match.status}}
    end
  end

  @doc "A page of the conversation, newest first, with the next (older) cursor."
  def messages(%{user_id: user_id} = context, match_id, params) do
    limit = Partners.message_page_limit(param(params, "limit"))

    with {:ok, match, scope, club} <- locate(context, match_id),
         {:ok, cursor} <- Partners.decode_message_cursor(param(params, "cursor")) do
      rows = Partners.list_messages(scope, match.id, cursor, limit + 1)
      {page, next_cursor} = Partners.message_page(rows, limit)
      people = people(match)

      {:ok,
       %{
         messages: Enum.map(page, &present_message(&1, user_id, people)),
         next_cursor: next_cursor,
         read_only: Partners.read_only?(match, writable_pair?(scope, club, match)),
         unread: Map.get(Partners.unread_counts(scope, user_id, [match]), match.id, 0)
       }}
    end
  end

  @doc "Writes a message into an active match and tells the other person once."
  def post(%{user_id: user_id} = context, match_id, params, now \\ DateTime.utc_now()) do
    with {:ok, match, scope, club} <- locate(context, match_id),
         :ok <- Partners.can_message?(match, writable_pair?(scope, club, match)),
         {:ok, body} <- Partners.normalize_message_body(param(params, "body")),
         {:ok, message} <-
           Partners.insert_message(
             scope,
             %{match_id: match.id, author_id: user_id, kind: "text", body: body},
             now
           ) do
      delivered(context, match, club, message)
      {:ok, present_message(message, user_id, people(match))}
    end
  end

  @doc "Marks the conversation read up to now for the viewer."
  def mark_read(%{user_id: user_id} = context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, match, scope, _club} <- locate(context, match_id) do
      unread = Map.get(Partners.unread_counts(scope, user_id, [match]), match.id, 0)

      if unread > 0 do
        {:ok, match} =
          Partners.update_match(scope, match, %{Partners.read_field(match, user_id) => now})

        PartnerRealtime.messages_read(match)
      end

      {:ok, %{read: unread}}
    end
  end

  @doc """
  «Κλείστε μαζί»: the gym's classes of the next days that suit both, those
  either of them booked first. Only for a club of a gym's own members
  (not an open club); for each class only whether these two are booked.
  """
  def sessions(%{user_id: user_id} = context, match_id, now \\ DateTime.utc_now()) do
    with {:ok, match, scope, club} <- locate(context, match_id) do
      if plannable?(club) and Partners.match_active?(match) do
        other_id = Partners.other_party(match, user_id)
        {from, to} = Partners.session_window(now)
        timezone = Organizations.organization_timezone(club.organization_id)

        suggestions =
          scope
          |> Scheduling.get_calendar_week(%{start_at: from, end_at: to})
          |> Partners.session_suggestions(
            [user_id, other_id],
            shared_times(scope, match),
            timezone,
            now
          )
          |> Enum.map(&present_session(&1, user_id, other_id))

        {:ok, %{available: true, timezone: timezone, sessions: suggestions}}
      else
        {:ok, %{available: false, timezone: nil, sessions: []}}
      end
    end
  end

  @doc "Posts a class as a «Κλείστε μαζί» plan, with an optional note."
  def plan(%{user_id: user_id} = context, match_id, params, now \\ DateTime.utc_now()) do
    with {:ok, match, scope, club} <- locate(context, match_id),
         true <- plannable?(club) || {:error, :partner_plans_unavailable},
         :ok <- Partners.can_message?(match, writable_pair?(scope, club, match)),
         {:ok, note} <- Partners.normalize_note(param(params, "body")),
         {:ok, slot} <- upcoming_slot(scope, param(params, "class_id"), now),
         {:ok, message} <-
           Partners.insert_message(
             scope,
             %{
               match_id: match.id,
               author_id: user_id,
               kind: "plan",
               body: note,
               scheduled_class_id: slot.id,
               plan: Partners.plan_snapshot(slot)
             },
             now
           ) do
      delivered(context, match, club, message)
      {:ok, present_message(message, user_id, people(match))}
    end
  end

  @doc "Ends the active matches between two people in the gyms of the viewer's clubs (a block)."
  def end_between(%{user_id: user_id} = context, other_id, reason, now \\ DateTime.utc_now()) do
    with {:ok, scopes} <- PartnerClubs.scopes(context) do
      scopes
      |> Enum.flat_map(fn scope ->
        Partners.end_matches(scope, %{pair: {user_id, other_id}}, %{
          status: "ended",
          end_reason: reason,
          ended_by_id: user_id,
          ended_at: now
        })
      end)
      |> Enum.each(&PartnerRealtime.match_changed/1)

      :ok
    end
  end

  # ------------------------------------------------------------- internals

  defp locate(%{user_id: user_id} = context, match_id) do
    with {:ok, clubs} <- ClubScope.call(context),
         {:ok, scopes} <- PartnerClubs.scopes(context) do
      Enum.find_value(scopes, {:error, :not_found}, fn scope ->
        case Partners.get_match(scope, match_id) do
          %{} = match ->
            if Partners.match_party?(match, user_id),
              do: {:ok, match, scope, Enum.find(clubs, &(&1.id == match.club_id))}

          nil ->
            nil
        end
      end)
    end
  end

  defp plannable?(%{kind: kind}), do: kind != "open"
  defp plannable?(_club), do: false

  # Both still in the club (a gym's word, now) and the club still offers Partners.
  defp writable_pair?(_scope, nil, _match), do: false

  defp writable_pair?(scope, club, match) do
    ids = PartnerClubs.eligible_ids(scope, club)

    match.user_a_id in ids and match.user_b_id in ids and
      PartnerClubs.offered(club, scope) == :ok
  end

  defp member_cache(rows, clubs) do
    rows
    |> Enum.map(fn {match, scope, _unread} -> {match.club_id, scope} end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Map.new(fn {club_id, scope} ->
      case Enum.find(clubs, &(&1.id == club_id)) do
        nil -> {club_id, MapSet.new()}
        club -> {club_id, MapSet.new(PartnerClubs.eligible_ids(scope, club))}
      end
    end)
  end

  defp both_members?(_members, nil, _match), do: false

  defp both_members?(members, club, match) do
    ids = Map.get(members, club.id, MapSet.new())
    MapSet.member?(ids, match.user_a_id) and MapSet.member?(ids, match.user_b_id)
  end

  defp shared_times(scope, match) do
    [match.user_a_id, match.user_b_id]
    |> Enum.map(&Partners.get_profile(scope, match.club_id, &1))
    |> case do
      [%{times: a}, %{times: b}] -> Enum.filter(a, &(&1 in b))
      _missing -> []
    end
  end

  defp upcoming_slot(scope, class_id, now) do
    with {:ok, class_id} <- cast_id(class_id),
         [slot] <- Scheduling.list_slots_by_ids(scope, [class_id]),
         :gt <- DateTime.compare(slot.scheduled_at, now) do
      {:ok, slot}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp delivered(%{user_id: user_id} = context, match, club, message) do
    PartnerRealtime.message_created(match)

    Notifications.dispatch_event(:partner_message, %{
      user_id: Partners.other_party(match, user_id),
      organization_id: club && club.organization_id,
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

  defp present(match, club, user_id, people, unread, both_members?) do
    %{
      id: match.id,
      club_id: match.club_id,
      club_name: club && club.name,
      person: CommunityPeople.person(people, Partners.other_party(match, user_id)),
      status: match.status,
      end_reason: match.end_reason,
      ended_by_me: match.ended_by_id == user_id,
      read_only: Partners.read_only?(match, both_members?),
      plannable: plannable?(club),
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
      class_id: plan["class_id"],
      name: plan["name"],
      scheduled_at: plan["scheduled_at"],
      duration_minutes: plan["duration_minutes"]
    }
  end

  defp present_session(%{slot: slot, booked: booked, shared_time: shared_time}, user_id, other_id) do
    %{
      class_id: slot.id,
      name: Partners.plan_snapshot(slot)["name"],
      scheduled_at: slot.scheduled_at,
      duration_minutes: slot.duration_minutes,
      spots_remaining: Map.get(slot, :spots_remaining, 0),
      booked_by_me: user_id in booked,
      booked_by_partner: other_id in booked,
      shared_time: shared_time
    }
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id || "") do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))

  defp param(_params, _key), do: nil
end
