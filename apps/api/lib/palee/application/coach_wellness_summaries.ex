defmodule Palee.Application.CoachWellnessSummaries do
  @moduledoc """
  The coach's Sunday wellness push (ADR-160 §4). When a member has
  «Ευεξία · εβδομαδιαία σύνοψη» on, each coach who coaches them (an active
  coaching relationship in a gym where the member is active) and may see
  their health data (`view_health`) hears, on Sunday at 19:00 in the
  member's zone, the week's counts: nights at the sleep goal, water days on
  goal, days with meals logged. Never craving times: those stay on the
  client page, behind the member's second toggle. The push links to the
  client page; a dedupe key holds it to one per coach, gym, member and week.

  A definer lookup names the members and their coaches (ids only); the
  counts are computed in the member's own session.
  """

  require Logger

  alias Palee.Application.{AuthorizeClientAccess, WellnessSummarySharing}
  alias Palee.Application.Buddies, as: BuddyPages
  alias Palee.{Buddies, Identity, Notifications, Organizations}

  @batch 500

  def call(now \\ DateTime.utc_now()) do
    @batch
    |> Buddies.wellness_summary_members()
    |> Enum.filter(&Buddies.summary_due?(&1.tz, now))
    |> Enum.each(&send_for(&1.user_id, &1.tz, now))

    :ok
  end

  @doc "One member's coach pushes for the week containing `now` (public for tests)."
  def send_for(user_id, tz, now) do
    member = %{user_id: user_id}
    toggles = member |> Buddies.list_summary_grants(user_id) |> Buddies.summary_toggles()

    with true <- toggles.wellness,
         [_ | _] = coaches <- Buddies.wellness_summary_coaches(user_id) do
      week = Buddies.summary_week(tz, now)
      # Counts only: the push never carries craving moments.
      summary = WellnessSummarySharing.compute(user_id, %{toggles | cravings: false}, week)
      client = Identity.find_by_id(user_id)

      coaches
      |> Enum.filter(&may_view?(&1, user_id))
      |> Enum.each(fn %{organization_id: organization_id, coach_user_id: coach_id} ->
        Notifications.dispatch_event(:coach_wellness_summary, %{
          user_id: coach_id,
          organization_id: organization_id,
          client_user_id: user_id,
          client_nickname: client && BuddyPages.nickname(client),
          week_start: summary.week_start,
          week_end: summary.week_end,
          sleep_nights: summary.sleep.nights_on_goal,
          water_days: summary.water.days_on_goal,
          meal_days: summary.meals.days_logged,
          dedupe_key: "coach_wellness_summary:#{organization_id}:#{user_id}:#{summary.week_start}"
        })
      end)
    end

    :ok
  rescue
    error ->
      Logger.error("coach wellness summary #{user_id} failed: #{Exception.message(error)}")
      :error
  end

  defp may_view?(%{organization_id: organization_id, coach_user_id: coach_id}, client_id) do
    with %{} = coach <- Identity.find_by_id(coach_id),
         {:ok, context} <- Organizations.resolve_tenant_context_by_id(coach, organization_id) do
      AuthorizeClientAccess.call(context, :view_health, client_id) == :ok
    else
      _no -> false
    end
  end
end
