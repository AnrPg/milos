defmodule Palee.Workers.PersonalDataExportJob do
  @moduledoc """
  ADR-267: builds one "Download my data" export in the person's own
  sessions. Retried while storage is briefly unavailable; the last attempt
  marks the export failed so the person can ask again.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker, :args], keys: [:export_id]]

  alias Palee.Application.PersonalDataExports

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "export_id" => export_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case PersonalDataExports.build(user_id, export_id) do
      {:ok, _outcome} ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts, do: PersonalDataExports.fail(user_id, export_id, reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)
end
