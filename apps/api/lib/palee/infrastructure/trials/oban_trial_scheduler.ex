defmodule Palee.Infrastructure.Trials.ObanTrialScheduler do
  @moduledoc "Oban adapter of the trial scheduler: one unique job per trial and step."

  @behaviour Palee.Trials.Ports.TrialScheduler

  require Logger

  alias Palee.Workers.TrialStepJob

  @impl true
  def schedule(organization_id, trial_id, steps) do
    if Application.get_env(:palee, :start_oban, true) do
      now = DateTime.utc_now()

      steps
      |> Enum.filter(fn {_step, at} -> DateTime.compare(at, now) == :gt end)
      |> Enum.each(fn {step, at} ->
        %{organization_id: organization_id, trial_id: trial_id, step: Atom.to_string(step)}
        |> TrialStepJob.new(scheduled_at: at)
        |> Oban.insert()
        |> case do
          {:ok, _job} -> :ok
          {:error, reason} -> Logger.warning("trial_step_schedule_failed #{inspect(reason)}")
        end
      end)
    end

    :ok
  end
end
