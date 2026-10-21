defmodule Palee.Organizations.Commands.AdvanceOrganizationPurge do
  @moduledoc """
  Moves a purge record through the ADR-117 state machine. Every transition
  locks the purge row inside a vendor-scoped RepoContext and validates the
  event against `Domain.PurgePolicy` before persisting.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.{OrganizationPurge, OrganizationStore, PlatformContext}
  alias Palee.Organizations.Domain.PurgePolicy

  @doc "Advances the purge identified by `purge_id` (job-driven stages)."
  def call(%PlatformContext{} = context, purge_id, event, attrs, at) do
    with {:ok, purge_id} <- cast_id(purge_id) do
      locked(context, fn -> lock_by_id(purge_id) end, fn purge ->
        apply_event(context, purge, event, attrs, at)
      end)
    end
  end

  def call(_context, _purge_id, _event, _attrs, _at), do: {:error, :vendor_required}

  @doc "Approves the organization's open purge after the typed slug confirmation."
  def approve(%PlatformContext{} = context, organization_id, confirmation, at) do
    with {:ok, organization_id} <- cast_id(organization_id) do
      locked(context, fn -> lock_open(organization_id) end, fn purge ->
        with :ok <- PurgePolicy.verify_confirmation(purge.organization_slug, confirmation) do
          apply_event(context, purge, :approve, %{}, at)
        end
      end)
    end
  end

  def approve(_context, _organization_id, _confirmation, _at), do: {:error, :vendor_required}

  @doc "Cancels the organization's open purge while it is still reversible."
  def cancel(%PlatformContext{} = context, organization_id, at) do
    with {:ok, organization_id} <- cast_id(organization_id) do
      locked(context, fn -> lock_open(organization_id) end, fn purge ->
        apply_event(context, purge, :cancel, %{}, at)
      end)
    end
  end

  def cancel(_context, _organization_id, _at), do: {:error, :vendor_required}

  defp locked(context, find, fun) do
    RepoContext.run(%{user_id: context.user_id}, fn ->
      OrganizationStore.transaction(fn ->
        case find.() do
          %OrganizationPurge{} = purge -> fun.(purge)
          nil -> {:error, :not_found}
        end
      end)
    end)
  end

  defp lock_by_id(purge_id), do: OrganizationStore.lock_purge(purge_id)

  defp lock_open(organization_id) do
    case OrganizationStore.get_open_purge(organization_id) do
      nil -> nil
      purge -> OrganizationStore.lock_purge(purge.id)
    end
  end

  defp apply_event(_context, purge, {:record_step, name, result}, _attrs, at) do
    if purge.status == :purging do
      OrganizationStore.update_purge(purge, %{
        steps: PurgePolicy.put_step(purge.steps, name, result, at)
      })
    else
      {:error, :invalid_purge_transition}
    end
  end

  defp apply_event(context, purge, event, attrs, at) do
    with {:ok, status} <- PurgePolicy.transition(purge, event) do
      OrganizationStore.update_purge(purge, params(event, status, purge, attrs, context, at))
    end
  end

  defp params(:start_export, status, _purge, _attrs, _context, at),
    do: %{status: status, export_started_at: at, failed_stage: nil, failure_reason: nil}

  defp params(:complete_export, status, _purge, attrs, _context, at) do
    attrs
    |> Map.take([
      :export_key,
      :export_byte_size,
      :export_sha256,
      :retained_archive_key,
      :retention_review
    ])
    |> Map.merge(%{status: status, export_completed_at: at})
  end

  defp params(:approve, status, purge, _attrs, context, at) do
    %{
      status: status,
      approved_by_user_id: context.user_id,
      approval_mode: PurgePolicy.approval_mode(purge.requested_by_user_id, context.user_id),
      approved_at: at
    }
  end

  defp params(:cancel, status, _purge, _attrs, context, at),
    do: %{status: status, cancelled_by_user_id: context.user_id, cancelled_at: at}

  defp params(:start_purge, status, purge, _attrs, _context, at) do
    %{
      status: status,
      purge_started_at: purge.purge_started_at || at,
      failed_stage: nil,
      failure_reason: nil
    }
  end

  defp params(:fail, status, _purge, attrs, _context, _at) do
    %{
      status: status,
      failed_stage: Map.fetch!(attrs, :stage),
      failure_reason: PurgePolicy.failure_reason(Map.get(attrs, :reason))
    }
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end
end
