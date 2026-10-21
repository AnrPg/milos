defmodule Palee.Workers.RebuildMemberSearchIndexJob do
  @moduledoc """
  Rebuilds the admin member search documents from the source of truth.

  Package, membership and package-type changes (including the ADR-096 family
  relabel) are reflected within one cron interval. The rebuild is idempotent
  and unique per interval, and search falls back to the database whenever the
  index is unavailable.
  """

  use Oban.Worker, queue: :analytics, max_attempts: 3, unique: [period: 600]

  alias Palee.Application.{AdminMemberSearchDocuments, AdminMemberSearchIndex}

  @impl Oban.Worker
  def perform(_job) do
    case AdminMemberSearchIndex.replace_documents(AdminMemberSearchDocuments.build_all()) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
