defmodule Palee.Workers.AbandonedDemosJob do
  @moduledoc """
  Daily: reminds the owners of idle demo businesses, then archives the ones
  still abandoned (ADR-184 follow-up, `Application.AbandonedDemos`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.AbandonedDemos

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _result} <- AbandonedDemos.call(), do: :ok
  end
end
