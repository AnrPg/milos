defmodule Palee.Buddies.Domain.WeeklySummary do
  @moduledoc """
  The buddy's optional weekly summary (ADR-160 §3, board 15 Q6): on Sunday
  at 19:00 in the member's zone, counts only: how many hard moments this
  week, how many were overcome, how many times they asked for support.
  Never times, causes, foods, intensity or notes; the composition takes
  only what it counts and returns only numbers and the week's dates.
  """

  @send_weekday 7
  @send_hour 19

  def send_hour, do: @send_hour

  @doc "Whether `now` is the Sunday 19:00 hour in `tz` (the job runs every half hour)."
  def due?(tz, %DateTime{} = now) do
    case local(now, tz) do
      {:ok, local} -> Date.day_of_week(local) == @send_weekday and local.hour == @send_hour
      :error -> false
    end
  end

  @doc "The Monday..Sunday week (local dates) that contains `now` in `tz`."
  def week(tz, %DateTime{} = now) do
    date =
      case local(now, tz) do
        {:ok, local} -> DateTime.to_date(local)
        :error -> DateTime.to_date(now)
      end

    from = Date.add(date, 1 - Date.day_of_week(date))
    {from, Date.add(from, 6)}
  end

  @doc "The last completed Monday..Sunday week before the one containing `now`."
  def previous_week(tz, now) do
    {from, _to} = week(tz, now)
    {Date.add(from, -7), Date.add(from, -1)}
  end

  @doc """
  The counts for a week. `cravings` are the member's live cravings of the
  week (only their `outcome` is looked at); `support_requests` is how many
  requests they sent and did not take back.
  """
  def compose({from, to}, cravings, support_requests) when is_integer(support_requests) do
    %{
      week_start: from,
      week_end: to,
      hard_moments: length(cravings),
      overcome: Enum.count(cravings, &(Map.get(&1, :outcome) == "resisted")),
      support_requests: support_requests
    }
  end

  @doc "One summary per buddy link and week, however often the job retries."
  def dedupe_key(link_id, %Date{} = week_start),
    do: "buddy_weekly_summary:#{link_id}:#{Date.to_iso8601(week_start)}"

  defp local(now, tz) do
    case DateTime.shift_zone(now, tz || "Etc/UTC") do
      {:ok, local} -> {:ok, local}
      {:error, _reason} -> :error
    end
  end
end
