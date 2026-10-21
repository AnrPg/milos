defmodule Palee.Workers.SeasonSweepJob do
  @moduledoc "Daily: seasons start running, finish, and their channels archive (ADR-167)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.SeasonSweep

  @impl Oban.Worker
  def perform(_job), do: SeasonSweep.call()
end
