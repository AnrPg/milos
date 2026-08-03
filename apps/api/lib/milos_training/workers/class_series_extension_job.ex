defmodule MilosTraining.Workers.ClassSeriesExtensionJob do
  use Oban.Worker, queue: :default, max_attempts: 5, unique: [period: 86_400]

  alias MilosTraining.Scheduling

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"series_id" => series_id, "horizon" => horizon}}) do
    with {:ok, horizon} <- Date.from_iso8601(horizon),
         {:ok, _series} <- Scheduling.extend_class_series(series_id, horizon) do
      :ok
    end
  end
end
