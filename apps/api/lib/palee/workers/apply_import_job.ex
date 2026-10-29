defmodule Palee.Workers.ApplyImportJob do
  @moduledoc """
  ADR-254: applies a queued CSV import, as the person who started it. Each
  row is applied once in its own transaction, so the job is safe to run
  again: a second run (or a retry from the screen) applies only the rows
  not yet applied. A crash leaves the import `failed` with the rows done so
  far; it is not retried automatically.
  """

  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [period: 60, keys: [:import_id], states: [:available, :scheduled, :executing]]

  alias Palee.Application.Imports.PeopleImports

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "import_id" => import_id,
          "user_id" => user_id
        }
      }) do
    PeopleImports.run_as(organization_id, import_id, user_id)
  end
end
