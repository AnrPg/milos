defmodule MilosTraining.Devices.Domain.ImportPolicy do
  @moduledoc """
  What an imported summary may do (ADR-161, board 16 Q3–Q4, Q7):

  - Everything from a device starts private, whatever the member's default
    for new entries, and is never posted on its own.
  - Sleep fills Ευεξία for its day and weight fills Σώμα, but anything the
    member typed for the same day wins: the import is kept (as the audit
    row's payload) and nothing visible changes.
  - The journal's device card counts what arrived since the member last
    looked and what still needs their answer.
  """

  @visibility "private"

  def visibility, do: @visibility

  @doc """
  `:import` or `{:manual_wins, entry_id}` for a night, given the day's
  sleep entries (naps never compete with a night).
  """
  def sleep_decision(entries) when is_list(entries) do
    case Enum.find(entries, &manual_night?/1) do
      nil -> :import
      entry -> {:manual_wins, entry.id}
    end
  end

  @doc "`:import` or `{:manual_wins, snapshot_id}` for a weigh-in, given the day's snapshots."
  def weight_decision(snapshots) when is_list(snapshots) do
    case Enum.find(snapshots, &manual_weight?/1) do
      nil -> :import
      snapshot -> {:manual_wins, snapshot.id}
    end
  end

  @doc """
  The device card: counts of imports since `seen_at` by kind, and how many
  activities wait for confirmation. `nil` when there is nothing to show.
  """
  def card(imports, pending_count, seen_at) do
    fresh =
      imports
      |> Enum.filter(&(&1.status in ["imported", "merged"]))
      |> Enum.filter(&after?(&1.received_at, seen_at))

    counts =
      fresh
      |> Enum.frequencies_by(& &1.kind)
      |> then(&Map.merge(%{"activity" => 0, "sleep" => 0, "weight" => 0, "daily" => 0}, &1))

    shown = counts["activity"] + counts["sleep"] + counts["weight"]

    %{
      new_counts: Map.delete(counts, "daily"),
      new_total: shown,
      needs_confirmation: pending_count,
      latest_at: fresh |> Enum.map(& &1.received_at) |> Enum.max(DateTime, fn -> nil end),
      visible: shown > 0 or pending_count > 0
    }
  end

  defp manual_night?(entry) do
    entry.kind == "sleep" and entry.source == "manual" and is_nil(Map.get(entry, :deleted_at)) and
      Map.get(entry.value || %{}, "nap", false) != true
  end

  defp manual_weight?(snapshot) do
    snapshot.source == "manual" and is_map(snapshot.metrics) and
      is_map_key(snapshot.metrics, "weight")
  end

  defp after?(_at, nil), do: true
  defp after?(at, seen_at), do: DateTime.compare(at, seen_at) == :gt
end
