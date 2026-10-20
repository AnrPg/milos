defmodule MilosTraining.Workers.BuddyWeeklySummaryJob do
  @moduledoc """
  Every half hour: for members whose Sunday 19:00 it is in their own zone,
  sends the weekly counts summary to buddies who get it, and the weekly
  wellness counts to coaches when the member shares them (ADR-160 §3, §4).
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 900]

  alias MilosTraining.Application.{BuddyWeeklySummaries, CoachWellnessSummaries}

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    :ok = BuddyWeeklySummaries.call(now)
    CoachWellnessSummaries.call(now)
  end
end
