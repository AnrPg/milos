defmodule MilosTraining.Application.BuddyWeeklySummaries do
  @moduledoc """
  The buddy's optional weekly summary (ADR-160 §3, board 15 Q6): on Sunday
  at 19:00 in the member's zone, each active buddy the member chose hears
  counts only: hard moments this week (Λιγούρα entries), how many were
  overcome, and how many times the member asked for support. Never times,
  causes, foods or notes. A definer lookup names who has such a buddy; each
  member is then handled in their own session, and the notification's
  dedupe key holds it to one per buddy and week however often the job
  runs.
  """

  require Logger

  alias MilosTraining.Application.Buddies, as: BuddyPages
  alias MilosTraining.{Buddies, Identity, Notifications, Wellness}

  @batch 500

  def call(now \\ DateTime.utc_now()) do
    @batch
    |> Buddies.summary_requesters()
    |> Enum.filter(&Buddies.summary_due?(&1.tz, now))
    |> Enum.each(&send_for(&1.user_id, &1.tz, now))

    :ok
  end

  @doc "One member's summaries for the week containing `now` (public for tests)."
  def send_for(user_id, tz, now) do
    context = %{user_id: user_id}
    summary = summary(context, user_id, tz, now)
    member = Identity.find_by_id(user_id)

    context
    |> Buddies.active_links_as_requester(user_id)
    |> Enum.filter(& &1.receives_weekly_summary)
    |> Enum.each(fn link ->
      Notifications.dispatch_event(:buddy_weekly_summary, %{
        user_id: link.buddy_user_id,
        member_id: user_id,
        member_nickname: member && BuddyPages.nickname(member),
        week_start: summary.week_start,
        week_end: summary.week_end,
        hard_moments: summary.hard_moments,
        overcome: summary.overcome,
        support_requests: summary.support_requests,
        dedupe_key: Buddies.summary_dedupe_key(link.id, summary.week_start)
      })
    end)

    :ok
  rescue
    error ->
      Logger.error("buddy weekly summary #{user_id} failed: #{Exception.message(error)}")
      :error
  end

  @doc "The counts for the member's week (Monday..Sunday in `tz`) containing `now`."
  def summary(context, user_id, tz, now) do
    {from, to} = week = Buddies.summary_week(tz, now)

    cravings =
      Wellness.with_context(context, fn -> Wellness.list_cravings(user_id, from, to) end)

    requests =
      Buddies.count_requests_between(
        context,
        user_id,
        midnight(from, tz),
        midnight(Date.add(to, 1), tz)
      )

    Buddies.compose_summary(week, cravings, requests)
  end

  # The UTC instant of a local midnight (DST gaps and folds resolved).
  defp midnight(date, tz) do
    local =
      case DateTime.new(date, ~T[00:00:00], tz) do
        {:ok, at} -> at
        {:ambiguous, first, _second} -> first
        {:gap, _before, just_after} -> just_after
        {:error, _reason} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end
end
