defmodule Palee.Workers.ExecuteAccountDeletionsJob do
  @moduledoc """
  Hourly: carries out the self-service deletions whose 7-day grace is over
  (ADR-211, `Application.AccountDeletion.execute_due/2`). A sweep rather
  than one job per deletion, so an undo needs no job to be found and
  cancelled, and a missed run catches up.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 1_800]

  alias Palee.Application.AccountDeletion

  @impl Oban.Worker
  def perform(_job) do
    _count = AccountDeletion.execute_due()
    :ok
  end
end
