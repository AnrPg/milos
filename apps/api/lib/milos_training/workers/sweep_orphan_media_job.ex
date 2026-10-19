defmodule MilosTraining.Workers.SweepOrphanMediaJob do
  @moduledoc "ADR-148: hourly removal of uploads nobody attached within a day."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 600]

  alias MilosTraining.Application.SweepOrphanMedia

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _deleted} <- SweepOrphanMedia.call(), do: :ok
  end
end
