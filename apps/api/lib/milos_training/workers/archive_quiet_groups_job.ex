defmodule MilosTraining.Workers.ArchiveQuietGroupsJob do
  @moduledoc "Daily: warns and archives member groups nobody posts in (ADR-143)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias MilosTraining.Application.ArchiveQuietGroups

  @impl Oban.Worker
  def perform(_job), do: ArchiveQuietGroups.call()
end
