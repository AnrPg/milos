defmodule Palee.Application.GetWodTodayCard do
  @moduledoc """
  The `#wod-σήμερα` card (ADR-138 D6): the gym's class WOD for one local
  day, its classes, and a leaderboard of that day's results (in-app
  executions and logged scores) from members who opted in to leaderboards,
  ranked by the WOD's scored section. A result kept `private` in its
  owner's journal never shows. Read in the gym's scope.
  """

  alias Palee.{Execution, Gamification, Identity, Scheduling, Workouts}
  alias Palee.Application.ClubScope

  @leaderboard_size 20

  def call(%{organization_id: _organization_id, user_id: user_id} = context, params) do
    with {:ok, timezone} <- timezone(param(params, :timezone)),
         {:ok, date} <- date(param(params, :date), timezone),
         {from, to} = window(date, timezone),
         {:ok, club} <- ClubScope.gym_club(context) do
      wod_channel = Enum.find(club.channels, &(&1.kind == "wod"))
      slots = context |> Scheduling.get_calendar_week(%{start_at: from, end_at: to}) |> slots()

      case first_workout(slots) do
        nil ->
          {:ok, empty(date, wod_channel)}

        workout_id ->
          workout = Workouts.get_workout(context, workout_id)
          section = ranked_section(workout)

          {:ok,
           %{
             date: date,
             channel_id: wod_channel && wod_channel.id,
             workout:
               workout && %{id: workout.id, title: workout.title, type: workout_type(workout)},
             classes:
               slots
               |> Enum.filter(&(&1.master_workout_id == workout_id))
               |> Enum.map(&%{id: &1.id, scheduled_at: &1.scheduled_at}),
             score: section && Map.take(section, [:id, :name, :score_type, :unit]),
             leaderboard: leaderboard(context, workout_id, section, from, to, user_id),
             logged_by_me: logged?(context, workout_id, from, to, user_id)
           }}
      end
    end
  end

  defp empty(date, wod_channel),
    do: %{
      date: date,
      channel_id: wod_channel && wod_channel.id,
      workout: nil,
      classes: [],
      score: nil,
      leaderboard: [],
      logged_by_me: false
    }

  defp leaderboard(context, workout_id, section, from, to, viewer_id) do
    results =
      context
      |> Execution.list_workout_results(workout_id, from, to)
      |> Enum.reject(&(&1.journal_visibility == "private"))

    opted_in =
      Gamification.with_tenant_context(context, fn ->
        results
        |> Enum.map(& &1.user_id)
        |> Enum.uniq()
        |> Gamification.leaderboard_opted_in_user_ids()
      end)
      |> MapSet.new()

    # The viewer sees their own place even before opting in; others only see
    # members who opted in.
    ranked =
      results
      |> Enum.filter(&(MapSet.member?(opted_in, &1.user_id) or &1.user_id == viewer_id))
      |> Execution.rank_workout_results(section)
      |> Enum.reject(&is_nil(&1.rank))
      |> Enum.take(@leaderboard_size)

    people = ranked |> Enum.map(& &1.user_id) |> people()

    Enum.map(ranked, fn row ->
      person = Map.get(people, row.user_id, %{})

      %{
        rank: row.rank,
        user_id: row.user_id,
        nickname: Map.get(person, :nickname),
        avatar_url: Map.get(person, :avatar_url),
        scale_level_slug: row.scale_level_slug,
        value: row.score && to_string(row.score["value"] || row.score[:value]),
        unit: row.score && (row.score["unit"] || row.score[:unit]),
        me: row.user_id == viewer_id,
        opted_in: MapSet.member?(opted_in, row.user_id)
      }
    end)
  end

  # The WOD's scored section; for a workout written in text sections
  # (ADR-179), the first score its coach set.
  defp ranked_section(workout) do
    case Execution.training_log_scoreable_sections(workout) do
      [section | _rest] -> section
      [] -> workout |> Execution.text_section_metrics() |> List.first()
    end
  end

  defp logged?(context, workout_id, from, to, user_id) do
    context
    |> Execution.list_workout_results(workout_id, from, to)
    |> Enum.any?(&(&1.user_id == user_id))
  end

  defp people([]), do: %{}
  defp people(ids), do: ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

  defp slots(slots) when is_list(slots), do: Enum.sort_by(slots, & &1.scheduled_at, DateTime)
  defp slots(_error), do: []

  defp first_workout(slots) do
    Enum.find_value(slots, fn slot -> slot[:master_workout_id] end)
  end

  defp workout_type(workout), do: workout |> Map.get(:type) |> then(&(&1 && to_string(&1)))

  defp window(date, timezone),
    do: {local_midnight(date, timezone), local_midnight(Date.add(date, 1), timezone)}

  # Midnight can be skipped or repeated by a DST change in some zones.
  defp local_midnight(date, timezone) do
    case DateTime.new(date, ~T[00:00:00], timezone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
    end
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp timezone(nil), do: {:ok, "Etc/UTC"}
  defp timezone(""), do: {:ok, "Etc/UTC"}

  defp timezone(timezone) when is_binary(timezone) do
    case DateTime.now(timezone) do
      {:ok, _now} -> {:ok, timezone}
      _invalid -> {:error, :invalid_timezone}
    end
  end

  defp date(nil, timezone), do: {:ok, DateTime.now!(timezone) |> DateTime.to_date()}
  defp date("", timezone), do: date(nil, timezone)
  defp date(%Date{} = date, _timezone), do: {:ok, date}

  defp date(value, _timezone) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, :invalid_date}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
