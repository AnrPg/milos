defmodule Palee.Devices.Domain.ImportPolicy do
  @moduledoc """
  What an imported summary may do (ADR-161, board 16 Q3–Q4, Q7):

  - Everything from a device starts private, whatever the member's default
    for new entries, and is never posted on its own.
  - Sleep fills Ευεξία for its day and weight fills Σώμα, but anything the
    member typed for the same day wins: the import is kept (as the audit
    row's payload) and nothing visible changes.
  - The journal's device card counts what arrived since the member last
    looked and what still needs their answer.
  - Two devices never double the same thing (ADR-172): a workout, night or
    weigh-in another connected device already brought in is kept only in
    the import log. The first to arrive wins; the phone often relays the
    same watch (Garmin Connect writes to Apple Health and Health Connect).
  """

  alias Palee.Devices.Domain.ActivityMatch

  @visibility "private"

  def visibility, do: @visibility

  @doc """
  `:import`, `{:manual_wins, entry_id}` or `{:other_device, entry_id}` for a
  night from `provider`, given the day's sleep entries (naps never compete
  with a night).
  """
  def sleep_decision(entries, provider) when is_list(entries) do
    nights = Enum.filter(entries, &night?/1)

    cond do
      manual = Enum.find(nights, &(&1.source == "manual")) -> {:manual_wins, manual.id}
      other = Enum.find(nights, &other_device?(&1.source, provider)) -> {:other_device, other.id}
      true -> :import
    end
  end

  @doc """
  `:import`, `{:manual_wins, snapshot_id}` or `{:other_device, snapshot_id}`
  for a weigh-in from `provider`, given the day's snapshots.
  """
  def weight_decision(snapshots, provider) when is_list(snapshots) do
    weighed = Enum.filter(snapshots, &weight?/1)

    cond do
      manual = Enum.find(weighed, &(&1.source == "manual")) -> {:manual_wins, manual.id}
      other = Enum.find(weighed, &other_device?(&1.source, provider)) -> {:other_device, other.id}
      true -> :import
    end
  end

  @doc """
  The id of a workout another device already brought in that this one
  overlaps (same rule as matching a class: start within 15 minutes or half
  the shorter one overlapping), or nil.
  """
  def other_device_activity(activity, device_activities, provider) do
    candidates =
      for other <- device_activities, other.provider != provider do
        %{
          kind: "device_activity",
          id: other.id,
          starts_at: other.started_at,
          ends_at: DateTime.add(other.started_at, other.duration_seconds, :second)
        }
      end

    case ActivityMatch.decide(activity, candidates, []) do
      :none -> nil
      {:merge, candidate} -> candidate.id
      {:ambiguous, [candidate | _rest]} -> candidate.id
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

  defp night?(entry) do
    entry.kind == "sleep" and is_nil(Map.get(entry, :deleted_at)) and
      Map.get(entry.value || %{}, "nap", false) != true
  end

  defp weight?(snapshot), do: is_map(snapshot.metrics) and is_map_key(snapshot.metrics, "weight")

  defp other_device?(source, provider), do: source not in ["manual", provider]

  defp after?(_at, nil), do: true
  defp after?(at, seen_at), do: DateTime.compare(at, seen_at) == :gt
end
