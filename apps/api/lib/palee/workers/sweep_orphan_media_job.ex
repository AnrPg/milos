defmodule Palee.Workers.SweepOrphanMediaJob do
  @moduledoc """
  ADR-148: hourly removal of uploads nobody attached within a day. ADR-157:
  the daily run (`dangling: true`) also releases uploads of posts that are gone.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 600]

  alias Palee.Application.SweepOrphanMedia

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    dangling? = Map.get(args || %{}, "dangling", false) == true

    with {:ok, _deleted} <- SweepOrphanMedia.call(DateTime.utc_now(), dangling: dangling?),
         do: :ok
  end
end
