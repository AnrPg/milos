defmodule Palee.Application.ComputeInsights do
  @moduledoc """
  Runs the insight rules for one person and stores the results (ADR-166).
  Everything is read in the person's own session over the last
  `Insights.window_days/0` days:

    * sessions from `AthleteTrainingVolume` (the same read as the Πρόοδος
      depth sections, ADR-165): instant, zone and perceived effort;
    * the days a PR was set (Pantheon history);
    * wellness day summaries (`Wellness.summarize_days`, against the
      member's own goals) and cravings, only when their journal section is
      on (Ρυθμίσεις, vision §8.6): a section that is off is not even read.
  """

  alias Palee.Application.AthleteTrainingVolume
  alias Palee.{Body, Insights, Pantheon, Wellness}

  @doc "Computes and stores; returns the stored rows. `settings` as `settings/2` gives them."
  def call(%{user_id: user_id} = context, %DateTime{} = now, settings \\ nil) do
    today = DateTime.to_date(now)
    from = Insights.window_start(today)
    settings = settings || settings(context, user_id)
    inputs = inputs(context, user_id, settings, from, today)
    results = Insights.evaluate(inputs, settings)

    Insights.with_context(context, fn ->
      :ok = Insights.put_results(user_id, results, from, today, now)
      Insights.list(user_id)
    end)
  end

  @doc """
  The member's current switches: journal sections (Body settings) and the
  wellness items they hid (Wellness preferences), with the sleep goal.
  """
  def settings(context, user_id) do
    body = Body.settings(context, user_id)
    prefs = Wellness.with_context(context, fn -> Wellness.preferences(user_id) end)

    %{
      sections: Map.new(Body.journal_sections(), &{&1, Body.section_on?(body, &1)}),
      hidden_items: prefs.hidden_items || [],
      prefs: prefs
    }
  end

  defp inputs(context, user_id, settings, from, today) do
    wellness? = settings.sections["wellness"]
    cravings? = settings.sections["cravings"]

    {entries, cravings} =
      Wellness.with_context(context, fn ->
        {
          if(wellness?, do: Wellness.list_entries(user_id, from, today), else: []),
          if(cravings?, do: Wellness.list_cravings(user_id, from, today), else: [])
        }
      end)

    %{
      today: today,
      from: from,
      sessions: sessions(context, from),
      pr_days: pr_days(context, user_id, from, today),
      days:
        if(wellness?,
          do:
            Wellness.summarize_days(
              Wellness.days_between(from, today),
              entries,
              [],
              %{},
              settings.prefs
            ),
          else: []
        ),
      cravings: cravings,
      sleep_goal_minutes: settings.prefs.sleep_goal_minutes
    }
  end

  defp sessions(context, from) do
    context
    |> AthleteTrainingVolume.load(DateTime.new!(from, ~T[00:00:00], "Etc/UTC"))
    |> Map.fetch!(:performances)
    |> Enum.map(&%{at: &1.at, tz: &1.tz, rpe: &1.rpe})
  end

  defp pr_days(context, user_id, from, today) do
    context
    |> Pantheon.with_user_context(fn -> Pantheon.list_user_record_history(user_id) end)
    |> Enum.flat_map(&date(&1.beaten_on))
    |> Enum.filter(&(Date.compare(&1, from) != :lt and Date.compare(&1, today) != :gt))
    |> Enum.uniq()
  end

  # The history read model gives ISO dates.
  defp date(%Date{} = day), do: [day]

  defp date(day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, day} -> [day]
      {:error, _reason} -> []
    end
  end

  defp date(_day), do: []
end
