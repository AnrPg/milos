defmodule MilosTraining.Coaching.CoachingStore do
  @behaviour MilosTraining.Coaching.Ports.CoachingStore

  defp adapter do
    Application.fetch_env!(:milos_training, :coaching_store)
  end

  @impl true
  def get_aggregates, do: adapter().get_aggregates()

  @impl true
  def refresh_aggregates, do: adapter().refresh_aggregates()
end
