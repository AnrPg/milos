defmodule Palee.Workers.ScalingSuggestionScanJob do
  @moduledoc "Hourly: queue AI scaling suggestions in gyms that switched them on (ADR-174)."

  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 1_800]

  alias Palee.Application.ScalingSuggestions

  @impl Oban.Worker
  def perform(_job) do
    ScalingSuggestions.scan_all()
    :ok
  end
end
