defmodule MilosTraining.Coaching.CoachingStore do
  @behaviour MilosTraining.Coaching.Ports.CoachingStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :coaching_store,
      MilosTraining.Infrastructure.Coaching.EctoCoachingStore
    )
  end

  @impl true
  def get_aggregates, do: adapter().get_aggregates()

  @impl true
  def refresh_aggregates, do: adapter().refresh_aggregates()
end
