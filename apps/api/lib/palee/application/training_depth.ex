defmodule Palee.Application.TrainingDepth do
  @moduledoc """
  The three Πρόοδος depth sections (ADR-165) built from one read of the
  athlete's training (`AthleteTrainingVolume`): muscle coverage (most and
  least trained major groups, push:pull and quad:ham), the qualities radar
  and training load. Shared by the member's own view and a coach's view of
  a client, so both always agree.

  - Coverage and qualities cover the chosen range (the Πρόοδος ranges, `all`
    from the first recorded session). Levels are per week, as in the atlas.
  - Load is always "as of today" (last 7 and 28 days, last 8 weeks):
    an acute:chronic ratio of a past window is not actionable.
  """

  alias Palee.Application.AthleteTrainingVolume
  alias Palee.{Analytics, Anatomy}

  @ranges ~w(4w 12w 6m 1y all)

  def ranges, do: @ranges

  @doc """
  Builds the sections for `range` as of `today`. `opts` go to
  `AthleteTrainingVolume.load/3` (`:user_id`, `:scope`); `:sources` keeps
  only performances from those source tokens (none = every source).
  """
  def build(context, range, %Date{} = today, opts \\ []) when range in @ranges do
    {sources, load_opts} = Keyword.pop(opts, :sources, [])
    range_from = range_start(range, today)
    load_from = Analytics.training_load_window_start(today)
    read_from = earliest(range_from, load_from)

    volume = AthleteTrainingVolume.load(context, midnight(read_from), load_opts)
    performances = Enum.filter(volume.performances, &source?(sources, &1.source))
    kept = MapSet.new(performances, &{&1.kind, &1.id})
    felt = Enum.filter(volume.felt, &MapSet.member?(kept, {&1.entry_kind, &1.entry_id}))

    in_range = Enum.filter(performances, &on_or_after?(&1, range_from))
    in_range_ids = MapSet.new(in_range, &{&1.kind, &1.id})
    felt_in_range = Enum.filter(felt, &MapSet.member?(in_range_ids, {&1.entry_kind, &1.entry_id}))

    from = range_from || first_day(in_range, today)
    weeks = weeks(from, today)
    coverage = Anatomy.coverage(in_range, felt_in_range, weeks)
    summary = Anatomy.coverage_summary(coverage.nodes, in_range)
    qualities = Anatomy.quality_profile(in_range, felt_in_range)

    %{
      range: range,
      from: from,
      to: today,
      weeks: weeks,
      coverage: %{
        sessions: coverage.sessions,
        exercises: coverage.exercises,
        felt_entries: length(felt_in_range),
        thresholds: Anatomy.coverage_thresholds(),
        most: summary.most,
        least: summary.least,
        balance: summary.balance
      },
      qualities:
        Map.put(qualities, :felt_entries, Enum.count(felt_in_range, &(&1.felt_qualities != []))),
      load:
        performances
        |> Enum.map(&%{on: DateTime.to_date(&1.at), rpe: &1.rpe, minutes: &1.minutes})
        |> Analytics.training_load(today)
        |> Map.put(:bands, Analytics.training_load_bands())
    }
  end

  defp range_start("all", _today), do: nil
  defp range_start("4w", today), do: Date.add(today, -27)
  defp range_start("12w", today), do: Date.add(today, -83)
  defp range_start("6m", today), do: Date.add(today, -181)
  defp range_start("1y", today), do: Date.add(today, -363)

  defp earliest(nil, _other), do: nil
  defp earliest(a, b), do: if(Date.compare(a, b) == :lt, do: a, else: b)

  defp midnight(nil), do: nil
  defp midnight(%Date{} = day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")

  defp on_or_after?(_performance, nil), do: true

  defp on_or_after?(performance, from),
    do: Date.compare(DateTime.to_date(performance.at), from) != :lt

  defp first_day([], today), do: today

  defp first_day(performances, _today),
    do: performances |> Enum.map(&DateTime.to_date(&1.at)) |> Enum.min(Date)

  # Whole weeks the range spans (at least one), for per-week levels.
  defp weeks(from, today), do: max(1, round((Date.diff(today, from) + 1) / 7))

  defp source?([], _source), do: true
  defp source?(sources, source), do: source in sources
end
