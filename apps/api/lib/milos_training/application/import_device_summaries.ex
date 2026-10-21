defmodule MilosTraining.Application.ImportDeviceSummaries do
  @moduledoc """
  The provider-neutral ingest (ADR-161, ADR-172). Garmin's push batches
  (one summary type for one connection, inline or behind a callback URL)
  and the phone's batches from Apple Health or Health Connect go through
  the same rules. Runs in the person's own session.

  Each record is imported once (`device_imports` is the dedupe key: a
  retried push or a re-read window changes nothing), only when the sync
  preferences want its kind; a night or a day's numbers sent again with
  different values replace what the earlier import set. Then:

  - a workout merges into the class or workout it overlaps, waits for the
    person when two could match, or becomes its own private entry
    (`ActivityMatch`, board 16 Q2–Q3);
  - a night fills Ευεξία for its day, unless the person typed one;
  - a weigh-in becomes a private Σώμα snapshot, unless the person typed a
    weight that day;
  - a day's resting heart rate and steps are kept for Πρόοδος;
  - anything another connected device already brought in is only logged
    (the phone often relays the same watch).

  Sleep, weight, heart rate and steps need the health-data consent (plan
  D8); without it they are logged as ignored and picked up when a later
  sync sends them again after the consent.
  """

  require Logger

  alias MilosTraining.Application.{DeviceTokens, WellnessConsent}
  alias MilosTraining.{Body, Devices, Wellness}

  @provider "garmin"

  @doc "Garmin job entry point: `connection_id`, `user_id`, `type`, `summaries` or `callback_url`."
  def run(%{"connection_id" => connection_id, "user_id" => user_id, "type" => type} = args) do
    context = %{user_id: user_id}
    now = DateTime.utc_now()

    case Devices.with_context(context, fn -> Devices.get_connection(user_id, @provider) end) do
      %{id: ^connection_id, status: status} = connection when status in ["active", "error"] ->
        with {:ok, summaries} <- summaries(context, connection, args, now) do
          result = import_all(context, connection, type, summaries, now)
          DeviceTokens.record_success(context, connection, now)
          {:ok, result}
        end

      _gone ->
        {:ok, :connection_gone}
    end
  end

  defp summaries(_context, _connection, %{"summaries" => summaries}, _now)
       when is_list(summaries),
       do: {:ok, summaries}

  defp summaries(context, connection, %{"callback_url" => url}, now) when is_binary(url) do
    with {:ok, token, connection} <- DeviceTokens.access_token(context, connection, now) do
      case Devices.garmin().fetch(token, url) do
        {:ok, summaries} ->
          {:ok, summaries}

        {:error, :invalid_callback_url} = error ->
          error

        {:error, reason} ->
          DeviceTokens.record_failure(context, connection, inspect(reason))
          {:error, reason}
      end
    end
  end

  defp summaries(_context, _connection, _args, _now), do: {:ok, []}

  @doc "Imports Garmin summaries of one type for a connection; returns counts by status."
  def import_all(context, connection, type, summaries, now) do
    kind = Devices.garmin_kind(type)
    consent? = WellnessConsent.active?(context, connection.user_id)

    summaries
    |> Enum.filter(&(Devices.garmin_user_id(&1) in [nil, connection.provider_user_id]))
    |> Enum.map(&import_if_wanted(context, connection, kind, &1, consent?, now))
    |> Enum.frequencies()
  end

  @doc """
  Imports a phone batch (`[{kind, records}]`, ADR-172) for a connection;
  returns counts by status.
  """
  def import_batches(context, connection, batches, now) do
    consent? = WellnessConsent.active?(context, connection.user_id)

    for {kind, records} <- batches, record <- records, reduce: %{} do
      counts ->
        status = import_if_wanted(context, connection, kind, record, consent?, now)
        Map.update(counts, status, 1, &(&1 + 1))
    end
  end

  defp import_if_wanted(context, connection, kind, record, consent?, now) do
    if kind && Devices.wanted?(connection.sync_prefs || %{}, kind),
      do: import_one(context, connection, kind, record, consent?, now),
      else: :skipped
  end

  defp import_one(context, connection, kind, summary, consent?, now) do
    provider = connection.provider
    provider_id = Devices.summary_provider_id(provider, kind, summary)
    user_id = connection.user_id
    payload = Devices.trim_summary(provider, kind, summary)

    existing =
      provider_id &&
        Devices.with_context(context, fn ->
          Devices.get_import(user_id, provider, kind, provider_id)
        end)

    cond do
      is_nil(provider_id) ->
        :invalid

      existing && not replace?(kind, existing, payload) ->
        :duplicate

      true ->
        base = %{
          connection_id: connection.id,
          user_id: user_id,
          provider: provider,
          kind: kind,
          provider_id: provider_id,
          payload: payload,
          received_at: now,
          existing: existing
        }

        context
        |> Devices.with_context(fn ->
          Devices.transaction(fn -> apply_kind(context, kind, summary, base, consent?) end)
        end)
        |> case do
          {:ok, import} ->
            String.to_atom(import.status)

          {:error, :duplicate_import} ->
            :duplicate

          {:error, reason} ->
            Logger.warning("device import #{kind} #{provider_id} failed #{inspect(reason)}")
            :failed
        end
    end
  end

  # A night or a day's numbers sent again replace the earlier import when
  # they changed, or when the earlier one was set aside (no consent then,
  # another device's night since deleted).
  defp replace?(kind, existing, payload) do
    Devices.replaceable_kind?(kind) and
      (existing.payload != payload or existing.status == "ignored")
  end

  defp apply_kind(context, "activity", summary, base, _consent?) do
    case Devices.read_summary(base.provider, "activity", summary) do
      {:ok, activity} -> import_activity(context, activity, base)
      {:error, reason} -> ignored(base, reason)
    end
  end

  defp apply_kind(_context, _kind, _summary, base, false),
    do: ignored(base, :health_data_consent_required)

  defp apply_kind(context, kind, summary, base, true) do
    case Devices.read_summary(base.provider, kind, summary) do
      {:ok, facts} -> import_health(context, kind, facts, base)
      {:error, reason} -> ignored(base, reason)
    end
  end

  defp import_health(context, "sleep", night, base), do: import_sleep(context, night, base)

  defp import_health(context, "weight", weigh_in, base),
    do: import_weight(context, weigh_in, base)

  defp import_health(_context, kind, day, base) when kind in ["daily", "steps"] do
    numbers =
      if kind == "daily",
        do: %{resting_heart_rate: day.resting_heart_rate},
        else: %{steps: day.steps}

    case Devices.upsert_daily_stat(
           Map.merge(numbers, %{user_id: base.user_id, on: day.on, source: base.provider})
         ) do
      {:ok, stat} -> record(base, "imported", "daily_stat", stat.id)
      {:error, reason} -> {:error, reason}
    end
  end

  # Workouts ------------------------------------------------------------------

  defp import_activity(_context, activity, base) do
    {from, to} = Devices.match_window(activity)
    others = Devices.list_activities_between(base.user_id, from, to)

    case Devices.other_device_activity(activity, others, base.provider) do
      nil -> import_new_activity(activity, base, from, to)
      other_id -> record(base, "ignored", "device_activity", other_id, "other_device_has_it")
    end
  end

  defp import_new_activity(activity, base, from, to) do
    candidates = Devices.match_candidates(from, to)
    taken = taken(candidates)

    attrs = %{
      user_id: base.user_id,
      provider: base.provider,
      provider_activity_id: activity.provider_id,
      sport: activity.sport,
      activity_type: activity.activity_type,
      title: activity.title || default_title(activity),
      started_at: activity.started_at,
      started_tz: activity.started_tz,
      duration_seconds: activity.duration_seconds,
      distance_meters: activity.distance_meters,
      avg_heart_rate: activity.avg_heart_rate,
      max_heart_rate: activity.max_heart_rate,
      calories: activity.calories,
      journal_visibility: Devices.import_visibility()
    }

    case Devices.match_activity(activity, candidates, taken) do
      {:merge, candidate} ->
        with {:ok, saved} <- Devices.insert_activity(Map.merge(attrs, merge_attrs(candidate))),
             do: record(base, "merged", "device_activity", saved.id)

      {:ambiguous, many} ->
        with {:ok, saved} <-
               Devices.insert_activity(
                 Map.merge(attrs, %{state: "pending", candidates: Enum.map(many, &stored/1)})
               ),
             do: record(base, "needs_confirmation", "device_activity", saved.id)

      :none ->
        with {:ok, saved} <- Devices.insert_activity(Map.put(attrs, :state, "own")),
             do: record(base, "imported", "device_activity", saved.id)
    end
  end

  @doc "What merging into a candidate sets on the watch workout."
  def merge_attrs(%{kind: "class"} = candidate),
    do: %{
      state: "own",
      class_id: candidate.id,
      organization_id: candidate.organization_id,
      title: candidate.title
    }

  def merge_attrs(candidate),
    do: %{
      state: "merged",
      merged_kind: candidate.kind,
      merged_id: candidate.id,
      organization_id: candidate.organization_id
    }

  defp taken(candidates) do
    candidates
    |> Enum.group_by(& &1.kind, & &1.id)
    |> Enum.flat_map(fn
      {"class", _ids} -> []
      {kind, ids} -> kind |> Devices.list_merged(ids) |> Enum.map(&{kind, &1.merged_id})
    end)
  end

  defp stored(candidate) do
    %{
      "kind" => candidate.kind,
      "id" => candidate.id,
      "organization_id" => candidate.organization_id,
      "title" => candidate.title,
      "starts_at" => DateTime.to_iso8601(candidate.starts_at),
      "ends_at" => DateTime.to_iso8601(candidate.ends_at)
    }
  end

  defp default_title(%{activity_type: type}) when is_binary(type) do
    type |> String.downcase() |> String.split("_") |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp default_title(_activity), do: "Workout"

  # Sleep -----------------------------------------------------------------------

  defp import_sleep(_context, night, base) do
    existing = Wellness.list_entries(base.user_id, night.on, night.on)

    case Devices.sleep_decision(Enum.filter(existing, &(&1.kind == "sleep")), base.provider) do
      {:manual_wins, entry_id} ->
        record(base, "merged", "wellness_entry", entry_id, "manual_entry_wins")

      {:other_device, entry_id} ->
        record(base, "ignored", "wellness_entry", entry_id, "other_device_has_it")

      :import ->
        value_params = %{
          "bed_at" => DateTime.to_iso8601(night.bed_at),
          "wake_at" => DateTime.to_iso8601(night.wake_at)
        }

        value_params =
          if night.quality,
            do: Map.put(value_params, "quality", night.quality),
            else: value_params

        with {:ok, value} <- Wellness.cast_value("sleep", value_params),
             {:ok, entry} <-
               Wellness.upsert_device_entry(%{
                 user_id: base.user_id,
                 kind: "sleep",
                 occurred_at: night.wake_at,
                 occurred_tz: night.tz,
                 occurred_on: night.on,
                 value: value,
                 source: base.provider,
                 external_id: night.provider_id,
                 journal_visibility: Devices.import_visibility()
               }) do
          record(base, "imported", "wellness_entry", entry.id)
        else
          {:error, {:invalid_wellness_value, _errors}} -> ignored(base, :invalid_sleep)
          error -> error
        end
    end
  end

  # Weight ----------------------------------------------------------------------

  defp import_weight(context, weigh_in, base) do
    since = weigh_in.on |> DateTime.new!(~T[00:00:00], "Etc/UTC") |> DateTime.add(-14 * 3600)

    same_day =
      context
      |> Body.list_snapshots(base.user_id, since: since, limit: 50)
      |> Enum.filter(&(local_date(&1.taken_at, &1.taken_tz) == weigh_in.on))

    case Devices.weight_decision(same_day, base.provider) do
      {:manual_wins, snapshot_id} ->
        record(base, "merged", "body_snapshot", snapshot_id, "manual_entry_wins")

      {:other_device, snapshot_id} ->
        record(base, "ignored", "body_snapshot", snapshot_id, "other_device_has_it")

      :import ->
        with {:ok, metrics} <- validate_metrics(weigh_in.metrics),
             {:ok, snapshot} <-
               Body.create_snapshot(context, %{
                 user_id: base.user_id,
                 taken_at: weigh_in.taken_at,
                 taken_tz: weigh_in.tz,
                 metrics: metrics,
                 visibility: "private",
                 source: base.provider
               }) do
          record(base, "imported", "body_snapshot", snapshot.id)
        else
          {:error, :invalid_weight} -> ignored(base, :invalid_weight)
          error -> error
        end
    end
  end

  defp validate_metrics(metrics) do
    case Body.validate_metrics(metrics, "metric") do
      {:ok, metrics} -> {:ok, Body.merge_metrics(%{}, metrics)}
      {:error, _reason, _details} -> {:error, :invalid_weight}
    end
  end

  defp local_date(at, zone) do
    case DateTime.shift_zone(at, zone || "Etc/UTC") do
      {:ok, local} -> DateTime.to_date(local)
      _unknown -> DateTime.to_date(at)
    end
  end

  # Records -------------------------------------------------------------------

  defp ignored(base, reason), do: record(base, "ignored", nil, nil, to_string(reason))

  # A first import inserts its log row; a replacement updates the earlier one.
  defp record(base, status, target_type, target_id, reason \\ nil) do
    {existing, base} = Map.pop(base, :existing)

    attrs =
      Map.merge(base, %{
        status: status,
        target_type: target_type,
        target_id: target_id,
        reason: reason
      })

    if existing,
      do: Devices.update_import(existing, attrs),
      else: Devices.insert_import(attrs)
  end
end
