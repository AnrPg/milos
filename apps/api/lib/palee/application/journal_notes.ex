defmodule Palee.Application.JournalNotes do
  @moduledoc """
  Σημείωση (ADR-139 §8, ADR-140): the member's own notes, written from
  Νέα καταχώρηση. Like a check-in, a note may name the gym it was written in
  (`organization_slug`), which gives it provenance and the member's `note`
  default rung; without a gym it is personal and private. Runs in the
  owner's scope.
  """

  alias Palee.Application.BroadcastUserSync
  alias Palee.{Journal, Organizations}

  def create(%{user_id: user_id, account: account} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, organization_id} <- provenance(account, params) do
      context
      |> Journal.with_context(fn -> Journal.write_note(user_id, organization_id, params, now) end)
      |> broadcast(user_id, "note_written")
    end
  end

  def update(%{user_id: user_id} = context, id, params) do
    context
    |> Journal.with_context(fn ->
      Journal.update_note(id, user_id, params, param(params, "lock_version"))
    end)
    |> broadcast(user_id, "note_updated")
  end

  def delete(%{user_id: user_id} = context, id) do
    context
    |> Journal.with_context(fn -> Journal.delete_note(id, user_id) end)
    |> broadcast(user_id, "note_deleted")
    |> case do
      {:ok, _note} -> :ok
      error -> error
    end
  end

  defp provenance(account, params) do
    case param(params, "organization_slug") do
      slug when is_binary(slug) and slug != "" ->
        case Organizations.resolve_tenant_context(account, slug) do
          {:ok, tenant} -> {:ok, tenant.organization_id}
          {:error, _reason} -> {:error, :note_organization_unavailable}
        end

      _personal ->
        {:ok, nil}
    end
  end

  defp broadcast({:ok, note} = ok, user_id, reason) do
    BroadcastUserSync.for_user(user_id, ["my_journal"],
      reason: reason,
      payload: %{note_id: note.id}
    )

    ok
  end

  defp broadcast(error, _user_id, _reason), do: error

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))
end
