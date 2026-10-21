defmodule Palee.Workers.WellnessNudgesJob do
  @moduledoc "Every 10 minutes: craving follow-ups and the opt-in afternoon water reminder (ADR-159)."

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 300]

  alias Palee.Application.WellnessNudges

  @impl Oban.Worker
  def perform(_job), do: WellnessNudges.call()
end
