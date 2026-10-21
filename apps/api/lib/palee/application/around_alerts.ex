defmodule Palee.Application.AroundAlerts do
  @moduledoc """
  The daily Γύρω μου alert sweep (ADR-154). For every named filter whose
  owner turned its alert on: claim today (Athens), count what matches it
  and was created since the filter last looked, and send one
  `around_new_matches` notification when there is something. The count asks
  only for items created after the last check, so it stays cheap; the
  notification's dedupe key holds it to one a day even if a job retries.

  The sweep learns which filters are due through a definer lookup and then
  works in each person's own session. A filter starts from its own
  neighbourhoods, else the person's saved area, else their box; with none
  of these it waits for another day. Boxes never alert people who already
  have a gym (plan §5a).
  """

  require Logger

  alias Palee.Application.AroundMe
  alias Palee.{Identity, Notifications, Places}

  @batch 200

  def call(now \\ DateTime.utc_now()) do
    day = Places.alert_day(now)
    sweep(day, now)
  end

  defp sweep(day, now) do
    case Identity.filter_alert_candidates(day, @batch) do
      [] ->
        :ok

      candidates ->
        Enum.each(candidates, &check(&1, day, now))
        sweep(day, now)
    end
  end

  @doc "One filter's alert for `day` (public for tests)."
  def check(%{id: id, user_id: user_id}, day, now) do
    context = %{user_id: user_id}

    with {:ok, claim} <- Identity.claim_filter_alert(context, id, day) do
      try do
        notify(context, claim, day, now)
      rescue
        error ->
          Logger.error("around alert #{id} failed: #{Exception.message(error)}")
          :error
      after
        Identity.finish_filter_alert(context, id, now)
      end
    end
  end

  defp notify(context, claim, day, now) do
    with {:ok, filter} <- Places.parse_filter(claim.params, AroundMe.vocabulary()),
         {:ok, origin} <- AroundMe.default_origin(context, filter) do
      plan =
        filter
        |> Places.plan(AroundMe.viewer(context.user_id), now, :alert)
        |> Places.created_after(claim.since)

      radius_m = filter.radius_km * 1000
      area = Places.circle(origin.points, radius_m)

      total =
        context
        |> Places.counts(area, plan, [radius_m])
        |> Map.values()
        |> Enum.map(&Map.get(&1, radius_m, 0))
        |> Enum.sum()

      if Places.notify_alert?(total) do
        Notifications.dispatch_event(:around_new_matches, %{
          user_id: context.user_id,
          filter_id: claim.id,
          filter_name: claim.name,
          count: total,
          dedupe_key: Places.alert_dedupe_key(claim.id, day)
        })
      end

      :ok
    else
      _nothing_to_check -> :ok
    end
  end
end
