defmodule MilosTraining.Workers.TrialStepJob do
  @moduledoc "Runs one timed step of a trial (ADR-144); see `Trials.Ports.TrialScheduler`."

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5,
    unique: [keys: [:trial_id, :step], period: :infinity, states: :incomplete]

  alias MilosTraining.Application.TrialSteps

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"organization_id" => organization_id, "trial_id" => trial_id, "step" => step}
      })
      when step in ~w(reminder expire follow_up) do
    TrialSteps.run(organization_id, trial_id, String.to_existing_atom(step))
  end
end
