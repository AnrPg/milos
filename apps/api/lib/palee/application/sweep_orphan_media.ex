defmodule Palee.Application.SweepOrphanMedia do
  @moduledoc """
  ADR-148: deletes uploads nobody attached within a day (abandoned editors,
  failed posts), gym by gym and person by person, each in its own scope.

  ADR-157: also rejects post uploads stuck before `ready` for a day (an
  upload that never finished, a lost job), so their post stops waiting and
  shows its author what failed; and, with `dangling: true` (daily), releases
  uploads still attached to a post that is gone (a purged gym, a release
  that failed when the post was deleted).
  """

  alias Palee.Application.{MediaConsumers, ReleaseMedia}
  alias Palee.{Media, Organizations}

  @batch 500

  def call(now \\ DateTime.utc_now(), opts \\ []) do
    cutoff = DateTime.add(now, -Media.orphan_after_seconds())

    tenant =
      for %{organization: organization} <- Organizations.list_active_organizations_for_system() do
        sweep(%{organization_id: organization.id}, :tenant, cutoff)
      end

    account =
      for user_id <- Media.account_orphan_owner_ids(cutoff) do
        sweep(%{user_id: user_id}, :account, cutoff)
      end

    stale = reject_stale(cutoff)
    dangling = if Keyword.get(opts, :dangling, false), do: release_dangling(cutoff), else: 0

    {:ok, Enum.sum(tenant) + Enum.sum(account) + stale + dangling}
  end

  defp sweep(context, scope, cutoff) do
    ids = context |> Media.list_unattached(scope, cutoff) |> Enum.map(& &1.id)
    :ok = ReleaseMedia.call(context, scope, ids)
    length(ids)
  end

  defp reject_stale(cutoff) do
    cutoff
    |> Media.stale_post_media(@batch)
    |> Enum.count(fn {user_id, media_id} ->
      context = %{user_id: user_id}

      case Media.mark_rejected(context, :account, media_id, :media_processing_timeout) do
        {:ok, media} ->
          MediaConsumers.refresh(context, media)
          true

        {:error, _changed} ->
          false
      end
    end)
  end

  defp release_dangling(cutoff) do
    cutoff
    |> Media.dangling_post_media(@batch)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {user_id, ids} ->
      :ok = ReleaseMedia.call(%{user_id: user_id}, :account, ids)
      length(ids)
    end)
    |> Enum.sum()
  end
end
