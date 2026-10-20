defmodule MilosTraining.Workers.BuddyWeeklySummaryJob do
  @moduledoc """
  Every half hour: sends the weekly counts summary to buddies who get it,
  for members whose Sunday 19:00 it is in their own zone (ADR-160 §3).
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 900]

  alias MilosTraining.Application.BuddyWeeklySummaries

  @impl Oban.Worker
  def perform(_job), do: BuddyWeeklySummaries.call()
end
