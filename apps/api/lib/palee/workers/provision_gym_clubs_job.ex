defmodule Palee.Workers.ProvisionGymClubsJob do
  @moduledoc """
  ADR-138 backfill and self-heal: makes sure every active gym has its club
  and built-in channels. Idempotent; scheduled hourly.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 600]

  alias Palee.Application.ProvisionGymClubs

  @impl Oban.Worker
  def perform(_job), do: ProvisionGymClubs.call()
end
