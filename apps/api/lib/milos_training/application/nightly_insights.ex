defmodule MilosTraining.Application.NightlyInsights do
  @moduledoc """
  The nightly insights run (ADR-166). A definer lookup names the people with
  any session, wellness entry or craving in the insight window (ids only,
  in id order); each is computed in their own session. One person's failure
  is logged and never stops the run.
  """

  require Logger

  alias MilosTraining.Application.ComputeInsights
  alias MilosTraining.Insights

  @batch 200

  def call(now \\ DateTime.utc_now()) do
    since = DateTime.new!(Insights.window_start(DateTime.to_date(now)), ~T[00:00:00], "Etc/UTC")
    sweep(since, nil, now, 0)
  end

  defp sweep(since, after_id, now, done) do
    case Insights.candidates(since, after_id, @batch) do
      [] ->
        {:ok, done}

      ids ->
        Enum.each(ids, &compute(&1, now))
        sweep(since, List.last(ids), now, done + length(ids))
    end
  end

  @doc "One person's run (public for tests)."
  def compute(user_id, now) do
    ComputeInsights.call(%{user_id: user_id}, now)
    :ok
  rescue
    error ->
      Logger.error("insights for #{user_id} failed: #{Exception.message(error)}")
      :error
  end
end
