defmodule MilosTraining.Workers.JournalExportJob do
  @moduledoc """
  ADR-162: builds a member's whole-journal export in their own session.
  Retried while storage is briefly unavailable; the last attempt marks the
  export failed so the member can ask again.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker, :args], keys: [:export_id]]

  alias MilosTraining.Application.JournalExports

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "export_id" => export_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    context = %{user_id: user_id}

    case JournalExports.build(context, export_id) do
      {:ok, _outcome} ->
        :ok

      {:error, reason} ->
        if attempt >= max_attempts, do: JournalExports.fail(context, export_id, reason)
        {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)
end
