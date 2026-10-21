defmodule MilosTraining.Devices.Domain.ActivityMatch do
  @moduledoc """
  Board 16, Q2 (A): a watch activity that overlaps a class the member booked
  or attended, a workout they logged or an in-app execution joins it instead
  of doubling it in the journal.

  A candidate matches when the activity starts within 15 minutes of the
  candidate's start, or when they overlap for at least half of the shorter
  of the two. One match merges; two or more ask the member once
  (`needs_confirmation`); none makes the activity its own entry.
  """

  @window_seconds 15 * 60

  @type candidate :: %{
          required(:kind) => String.t(),
          required(:id) => Ecto.UUID.t(),
          required(:starts_at) => DateTime.t(),
          required(:ends_at) => DateTime.t(),
          optional(atom()) => term()
        }

  @doc "Minutes of slack around a candidate's start."
  def window_seconds, do: @window_seconds

  @doc """
  `{:merge, candidate}`, `{:ambiguous, candidates}` or `:none`. `taken` lists
  `{kind, id}` pairs that already hold another activity's numbers.
  """
  def decide(%{started_at: started_at, duration_seconds: duration}, candidates, taken \\ []) do
    ends_at = DateTime.add(started_at, max(duration, 0), :second)

    candidates
    |> Enum.reject(&({&1.kind, &1.id} in taken))
    |> Enum.filter(&matches?(started_at, ends_at, &1))
    |> Enum.uniq_by(&{&1.kind, &1.id})
    |> case do
      [] -> :none
      [candidate] -> {:merge, candidate}
      many -> {:ambiguous, Enum.sort_by(many, & &1.starts_at, DateTime)}
    end
  end

  @doc "The instants a candidate search must cover around an activity."
  def search_window(%{started_at: started_at, duration_seconds: duration}) do
    {DateTime.add(started_at, -@window_seconds - 4 * 3600, :second),
     DateTime.add(started_at, max(duration, 0) + @window_seconds, :second)}
  end

  defp matches?(started_at, ends_at, candidate) do
    near_start?(started_at, candidate.starts_at) or
      half_overlap?(started_at, ends_at, candidate.starts_at, candidate.ends_at)
  end

  defp near_start?(a, b), do: abs(DateTime.diff(a, b, :second)) <= @window_seconds

  defp half_overlap?(a_start, a_end, b_start, b_end) do
    overlap =
      DateTime.diff(min_time(a_end, b_end), max_time(a_start, b_start), :second)

    shorter = min(DateTime.diff(a_end, a_start, :second), DateTime.diff(b_end, b_start, :second))
    shorter > 0 and overlap > 0 and overlap * 2 >= shorter
  end

  defp min_time(a, b), do: if(DateTime.compare(a, b) == :gt, do: b, else: a)
  defp max_time(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
end
