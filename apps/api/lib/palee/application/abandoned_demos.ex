defmodule Palee.Application.AbandonedDemos do
  @moduledoc """
  ADR-184 follow-up: demo businesses nobody uses are reminded, then archived
  (`BusinessAccounts.Domain.DemoLifecyclePolicy` defines last activity and
  the thresholds, `config :palee, :abandoned_demos`).

  - `call/1`, the daily sweep (`Workers.AbandonedDemosJob`):
    - idle past the reminder threshold: the reminder is claimed
      (`demo_reminder_sent_at`) and each owner gets one `business_demo_idle`
      notification, deduplicated per demo and idle spell;
    - idle past the archive threshold and reminded long enough ago: in one
      transaction the demo is archived, its tracked demo data and mock
      people are removed (the wipe activation runs), and its pending
      activation request and live link are withdrawn. The owners' accounts
      and everything they configured themselves stay.
  - `list_archived/1` and `reopen/3`: the owner brings an archived demo
    back, empty, with a fresh clock (Εγώ › Ρυθμίσεις, and sign-up or a
    conversion request of the same kind, `reopen_for_kind/3`). A new
    activation request is filed for it.
  """

  require Logger

  alias Palee.Application.DemoData
  alias Palee.{BusinessAccounts, Notifications, Organizations}

  @doc "The daily sweep. `{:ok, %{reminded: n, archived: n}}`."
  def call(now \\ DateTime.utc_now()) do
    thresholds = BusinessAccounts.demo_lifecycle_thresholds()

    now
    |> BusinessAccounts.demo_reminder_cutoff(thresholds)
    |> BusinessAccounts.idle_demo_organizations()
    |> Enum.reduce(%{reminded: 0, archived: 0}, fn candidate, counts ->
      case BusinessAccounts.demo_lifecycle_stage(candidate, now, thresholds) do
        :remind -> count(counts, :reminded, remind(candidate, now, thresholds))
        :archive -> count(counts, :archived, archive(candidate, now, thresholds))
        :keep -> counts
      end
    end)
    |> then(&{:ok, &1})
  end

  defp count(counts, key, {:ok, true}), do: Map.update!(counts, key, &(&1 + 1))
  defp count(counts, _key, _skipped_or_failed), do: counts

  defp remind(%{organization_id: organization_id, owner_ids: owner_ids}, now, thresholds) do
    BusinessAccounts.transaction(fn ->
      case BusinessAccounts.claim_demo_reminder(
             organization_id,
             BusinessAccounts.demo_reminder_cutoff(now, thresholds),
             now
           ) do
        {:ok, last_active_at} ->
          notify_owners(organization_id, owner_ids, last_active_at, thresholds)
          {:ok, true}

        :not_claimed ->
          {:ok, false}
      end
    end)
    |> log_failure("reminder", organization_id)
  end

  defp notify_owners(organization_id, owner_ids, last_active_at, thresholds) do
    organization = Organizations.get_by_id(organization_id)

    payload = %{
      organization_id: organization_id,
      business_name: organization && organization.name,
      business_kind: organization && organization.provider_kind,
      days_left: BusinessAccounts.demo_notice_days(thresholds),
      archive_on: Date.to_iso8601(BusinessAccounts.demo_archive_on(last_active_at, thresholds)),
      dedupe_key: BusinessAccounts.demo_reminder_dedupe_key(organization_id, last_active_at)
    }

    Enum.each(owner_ids, fn owner_id ->
      Notifications.dispatch_event(:business_demo_idle, Map.put(payload, :user_id, owner_id))
    end)
  end

  defp archive(%{organization_id: organization_id, owner_ids: owner_ids}, now, thresholds) do
    BusinessAccounts.transaction(fn ->
      if BusinessAccounts.mark_demo_archived(
           organization_id,
           BusinessAccounts.demo_archive_cutoff(now, thresholds),
           BusinessAccounts.demo_reminded_cutoff(now, thresholds),
           now
         ) do
        with {:ok, _removed} <-
               DemoData.wipe(%{organization_id: organization_id}, keep_user_ids: owner_ids),
             :ok <- BusinessAccounts.close_demo_activation(organization_id, now) do
          {:ok, true}
        end
      else
        {:ok, false}
      end
    end)
    |> log_failure("archive", organization_id)
  end

  defp log_failure({:ok, _done} = result, _step, _organization_id), do: result

  defp log_failure(error, step, organization_id) do
    Logger.error(
      "abandoned demo #{step} failed organization_id=#{organization_id} reason=#{inspect(error)}"
    )

    error
  end

  ## The owner

  @doc "The account's demo businesses the sweep archived."
  def list_archived(account), do: {:ok, BusinessAccounts.list_archived_demos(account)}

  @doc """
  Reopens an archived demo of `account` (its owner): active and empty, with
  a fresh clock, and a new activation request for the platform team.
  `details` names the request (default: the business itself).
  """
  def reopen(account, organization_id, details \\ %{}, now \\ DateTime.utc_now()) do
    with :ok <- no_live_demo(account) do
      reopen_now(account, organization_id, details, now)
    end
  end

  defp reopen_now(account, organization_id, details, now) do
    BusinessAccounts.transaction(fn ->
      with {:ok, id} <- BusinessAccounts.reopen_demo_business(account, organization_id, now),
           %{} = organization <- Organizations.get_by_id(id) || {:error, :not_found},
           {:ok, request} <- file_activation(account, organization, details) do
        {:ok, %{organization: organization, request: request}}
      end
    end)
  end

  @doc """
  Sign-up and conversion: the account's archived demo of `kind`, reopened,
  or `:none` when it has none (a new business is then opened).
  """
  def reopen_for_kind(account, kind, details \\ %{}, now \\ DateTime.utc_now()) do
    case Enum.find(BusinessAccounts.list_archived_demos(account), &(&1.provider_kind == kind)) do
      %{id: organization_id} -> reopen(account, organization_id, details, now)
      nil -> :none
    end
  end

  # ADR-184: an account runs at most one business still in demo mode.
  defp no_live_demo(account) do
    account
    |> Organizations.list_memberships()
    |> Enum.any?(fn %{membership: membership, organization: organization} ->
      :owner in membership.roles and Organizations.business_gated?(organization)
    end)
    |> if(do: {:error, :business_account_exists}, else: :ok)
  end

  defp file_activation(account, organization, details) do
    request = %{
      business_kind: organization.provider_kind,
      business_name: organization.name,
      city: Map.get(details, :city),
      phone: Map.get(details, :phone),
      message: Map.get(details, :message)
    }

    BusinessAccounts.file_request(account, "activation", request, organization.id)
  end
end
