defmodule MilosTraining.Workers.ExportOrganizationTenantDataJob do
  @moduledoc "ADR-099 stage 2: builds the tenant export and retention archive."

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: :infinity, fields: [:worker, :args], keys: [:purge_id], states: :incomplete]

  alias MilosTraining.Application.{ExportOrganizationTenantData, ResolveJobPlatformContext}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"purge_id" => purge_id, "actor_user_id" => actor_user_id}}) do
    result =
      with {:ok, platform_context} <-
             ResolveJobPlatformContext.call(actor_user_id, inspect(__MODULE__)),
           {:ok, _purge} <- ExportOrganizationTenantData.call(platform_context, purge_id) do
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
