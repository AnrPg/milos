defmodule Palee.Workers.OrganiserCleanupJob do
  @moduledoc "Daily: archives organiser organisations that never got an event (ADR-185)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.OrganiserCleanup

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _result} <- OrganiserCleanup.call(), do: :ok
  end
end
