defmodule MilosTraining.Workers.WalletPushJob do
  @moduledoc """
  Tells Apple (APNs) or Google (Wallet REST API) that a member's card changed
  (ADR-155). One pending job per pass: changes in quick succession collapse
  into one update, since the platform always fetches the latest card.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 8,
    unique: [keys: [:pass_id], period: 60, states: [:available, :scheduled, :retryable]]

  require Logger

  alias MilosTraining.Application.{OwnershipKeys, WalletPasses}

  def schedule(organization_id, pass_id) do
    if Oban.whereis(Oban) do
      %{organization_id: organization_id, pass_id: pass_id}
      |> new(schedule_in: 2)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> Logger.warning("wallet_push_schedule_failed #{inspect(reason)}")
      end
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with {:ok, %{"organization_id" => organization_id, "pass_id" => pass_id}} <-
           OwnershipKeys.require_tenant_args(args) do
      case WalletPasses.push(organization_id, pass_id) do
        {:error, :not_found} -> :ok
        other -> other
      end
    end
  end
end
