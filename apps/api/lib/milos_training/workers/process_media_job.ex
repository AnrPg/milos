defmodule MilosTraining.Workers.ProcessMediaJob do
  @moduledoc """
  ADR-157: processes a post photo or video in its owner's session. Retried
  when storage is briefly unavailable; the last attempt rejects the upload.
  """

  use Oban.Worker,
    queue: :media,
    max_attempts: 3,
    unique: [period: 300, fields: [:worker, :args], keys: [:media_id]]

  alias MilosTraining.Application.ProcessMedia

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"user_id" => user_id, "media_id" => media_id},
        attempt: attempt,
        max_attempts: max_attempts
      }) do
    case ProcessMedia.call(%{user_id: user_id}, media_id, final: attempt >= max_attempts) do
      {:ok, _outcome} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)
end
