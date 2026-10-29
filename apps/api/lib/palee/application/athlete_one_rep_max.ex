defmodule Palee.Application.AthleteOneRepMax do
  @moduledoc """
  ADR-270: an athlete's 1RM per exercise from their PRs, so a plan load in %
  of 1RM counts in kg wherever plan workouts are counted (training volume,
  history, progress, analytics), as the web runner already shows it.

  The PRs are read in the caller's session (`context`), so row security
  decides: the athlete reads their own; staff read what a PR's visibility
  admits, and nothing else counts. Unreadable PRs mean no 1RM.
  """

  alias Palee.Pantheon
  alias Palee.Workouts.Queries.PlanPrescriptions

  @doc "`fn name, exercise_ref -> kg | nil end` for `user_id`'s kg one-rep-max PRs."
  def lookup(context, user_id) when is_binary(user_id) do
    prs =
      case Pantheon.with_user_context(context, fn -> Pantheon.list_records(user_id) end) do
        records when is_list(records) -> records
        _unreadable -> []
      end

    PlanPrescriptions.one_rep_max_lookup(prs)
  end

  def lookup(_context, _user_id), do: PlanPrescriptions.one_rep_max_lookup([])
end
