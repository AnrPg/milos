defmodule Palee.Workers.ExecuteOrganizationPurgeJob do
  @moduledoc """
  ADR-117 stage 5: purges an approved tenant context-by-context. The service is
  idempotent, so Oban retries resume from the first unfinished step.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:purge_id], states: :incomplete]

  alias Palee.Application.{ExecuteOrganizationPurge, ResolveJobPlatformContext}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"purge_id" => purge_id, "actor_user_id" => actor_user_id}}) do
    result =
      with {:ok, platform_context} <-
             ResolveJobPlatformContext.call(actor_user_id, inspect(__MODULE__)),
           {:ok, _purge} <- ExecuteOrganizationPurge.call(platform_context, purge_id) do
        :ok
      end

    discard_unrunnable(result)
  end

  # A purge that moved on (cancelled, already exported/approved, completed) or a
  # vendor that lost authority will never succeed on retry.
  defp discard_unrunnable({:error, reason})
       when reason in [:invalid_purge_transition, :not_found, :vendor_required],
       do: {:cancel, reason}

  defp discard_unrunnable(result), do: result
end
