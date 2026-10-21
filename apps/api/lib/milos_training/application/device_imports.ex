defmodule MilosTraining.Application.DeviceImports do
  @moduledoc """
  What arrived from a device, as the member meets it (ADR-161):

  - the journal's device card (board 16 Q7): «Garmin · 2 νέες προπονήσεις ·
    1 χρειάζεται επιβεβαίωση», only when there is something new, gone once
    seen (`summary/1`, `mark_seen/2`);
  - the workouts waiting for an answer («Ήταν αυτό το CrossFit 18:00;»)
    and the answer (`pending/1`, `confirm/3`);
  - watch workouts of their own in Ροή, and the watch's numbers on the
    entries they merged into (`feed_entries/4`, `attach/2`).
  """

  alias MilosTraining.Application.{DevicePresenter, ImportDeviceSummaries}
  alias MilosTraining.Devices

  @provider "garmin"

  def summary(%{user_id: user_id} = context) do
    Devices.with_context(context, fn ->
      connection = Devices.get_connection(user_id, @provider)
      seen_at = connection && connection.imports_seen_at
      imports = Devices.list_imports_since(user_id, seen_at)
      pending = Devices.list_pending_activities(user_id)

      card = Devices.device_card(imports, length(pending), seen_at)

      {:ok,
       Map.merge(card, %{
         provider: @provider,
         connected: connection != nil and connection.status in ["active", "error"],
         status: connection && connection.status,
         backfill_progress: connection && Devices.backfill_progress(connection),
         seen_at: seen_at
       })}
    end)
  end

  def mark_seen(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    Devices.with_context(context, fn ->
      case Devices.get_connection(user_id, @provider) do
        nil ->
          {:error, :device_not_connected}

        connection ->
          with {:ok, _connection} <-
                 Devices.update_connection(connection, %{imports_seen_at: now}),
               do: summary(context)
      end
    end)
  end

  def pending(%{user_id: user_id} = context) do
    Devices.with_context(context, fn ->
      activities = Devices.list_pending_activities(user_id)
      imports = Map.new(Devices.list_imports_since(user_id, nil), &{&1.target_id, &1})

      {:ok,
       Enum.flat_map(activities, fn activity ->
         case Map.get(imports, activity.id) do
           %{status: "needs_confirmation"} = import ->
             [
               %{
                 id: import.id,
                 kind: import.kind,
                 received_at: import.received_at,
                 activity: DevicePresenter.activity(activity)
               }
             ]

           _none ->
             []
         end
       end)}
    end)
  end

  @doc """
  The member's answer to a waiting workout: `target_id` (one of its
  candidates) merges it there; `as_new: true` keeps it as its own entry.
  """
  def confirm(%{user_id: user_id} = context, import_id, params) do
    Devices.with_context(context, fn ->
      Devices.transaction(fn ->
        with %{status: "needs_confirmation", target_id: activity_id} = import <-
               Devices.get_import_by_id(import_id, user_id) || {:error, :not_found},
             %{state: "pending"} = activity <-
               Devices.get_activity(activity_id, user_id) || {:error, :not_found},
             {:ok, attrs, status} <- answer(activity, params),
             {:ok, updated} <- Devices.update_activity(activity, Map.put(attrs, :candidates, [])),
             {:ok, _import} <- Devices.update_import(import, %{status: status}) do
          {:ok, DevicePresenter.activity(updated)}
        else
          %{} -> {:error, :import_already_settled}
          error -> error
        end
      end)
    end)
  end

  defp answer(activity, params) do
    target_id = param(params, "target_id")

    cond do
      param(params, "as_new") in [true, "true"] ->
        {:ok, %{state: "own"}, "imported"}

      is_binary(target_id) ->
        case Enum.find(activity.candidates, &(&1["id"] == target_id)) do
          nil ->
            {:error, :unknown_device_candidate}

          candidate ->
            {:ok,
             ImportDeviceSummaries.merge_attrs(%{
               kind: candidate["kind"],
               id: candidate["id"],
               organization_id: candidate["organization_id"],
               title: candidate["title"]
             }), "merged"}
        end

      true ->
        {:error, :device_confirmation_required}
    end
  end

  @doc "Watch workouts of their own, as journal feed entries (run in the caller's session)."
  def feed_entries(user_id, bound, limit, scope) do
    user_id
    |> Devices.list_activity_items(bound, limit, scope)
    |> Enum.map(&DevicePresenter.activity/1)
  end

  @doc "Adds `device` (the watch's numbers, or nil) to journal entries of `kind`."
  def attach(entries, kind) when kind in ["training_log", "execution"] and is_list(entries) do
    by_entry =
      kind
      |> Devices.list_merged(Enum.map(entries, & &1.id))
      |> Map.new(&{&1.merged_id, DevicePresenter.metrics(&1)})

    Enum.map(entries, &Map.put(&1, :device, Map.get(by_entry, &1.id)))
  end

  # Request bodies arrive with string keys, or atom keys once cast by OpenApiSpex.
  defp param(params, key) when is_map(params) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        value

      :error ->
        Enum.find_value(params, fn {k, v} -> if is_atom(k) and Atom.to_string(k) == key, do: v end)
    end
  end

  defp param(_params, _key), do: nil
end
