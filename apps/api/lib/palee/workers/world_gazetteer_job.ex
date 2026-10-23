defmodule Palee.Workers.WorldGazetteerJob do
  @moduledoc """
  Hourly check, monthly work: imports the worldwide towns when the
  gazetteer has none or they are a month old (ADR-188, `Application.WorldGazetteer`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.WorldGazetteer

  @impl Oban.Worker
  def perform(_job) do
    with {:ok, _result} <- WorldGazetteer.refresh_if_stale(), do: :ok
  end
end
