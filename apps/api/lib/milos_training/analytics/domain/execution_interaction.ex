defmodule MilosTraining.Analytics.Domain.ExecutionInteraction do
  @moduledoc """
  Allowlist and validation for client-only workout-execution interaction
  signals (ADR-113). These are facts only the client can observe - a pause
  sheet opening, a manual skip versus an automatic segment advance, a
  "+1 round" tap, a get-ready countdown - and they arrive in batches through
  `POST /api/executions/:id/interactions`.

  Every interaction is `{client_event_id, kind, occurred_at, metadata}`:

  * `client_event_id` - a client-generated UUID; it is the idempotency key,
    so offline retries of the same batch never double count.
  * `kind` - one of `kinds/0`; anything else rejects the whole batch.
  * `occurred_at` - ISO-8601; must be within the last #{7} days and at most
    5 minutes in the future (clock skew), relative to the injected `now`.
  * `metadata` - only the typed fields allowed for that kind (see
    `allowed_fields/1`). Unknown keys, wrong types or out-of-range values
    reject the batch. There is no free-text field by design.

  Extending: add the kind to `@kinds_fields` with the subset of `@fields` it
  may carry (and, if needed, a new typed field to `@fields`). No migration,
  endpoint or OpenAPI schema change is needed beyond the enum.
  """

  @max_batch 50
  @max_age_seconds 7 * 86_400
  @max_skew_seconds 300
  @max_ms 86_400_000

  @surfaces ~w(pause_sheet primary_action header gesture keyboard snackbar ready_screen
               finish_wizard cast_display lock_screen)
  @orientations ~w(portrait landscape)
  @cue_channels ~w(sound voice vibration)

  # field => validator
  @fields %{
    "segment_index" => {:integer, 0, 10_000},
    "section_id" => :token,
    "format" => :token,
    "surface" => {:enum, @surfaces},
    "round_count" => {:integer, 0, 10_000},
    "delta_rounds" => {:integer, -100, 100},
    "delta_seconds" => {:integer, -3_600, 3_600},
    "elapsed_ms" => {:integer, 0, @max_ms},
    "remaining_ms" => {:integer, 0, @max_ms},
    "duration_ms" => {:integer, 0, @max_ms},
    "countdown_seconds" => {:integer, 0, 600},
    "step" => {:integer, 0, 20},
    "scored_section_count" => {:integer, 0, 1_000},
    "enabled" => :boolean,
    "orientation" => {:enum, @orientations},
    "cue_channel" => {:enum, @cue_channels}
  }

  @position ~w(segment_index section_id format surface)

  @kinds_fields %{
    # Pause sheet / pause control (audit U2, U9)
    "pause" => @position ++ ~w(elapsed_ms),
    "resume" => @position ++ ~w(duration_ms),
    "segment_skipped" => @position ++ ~w(elapsed_ms remaining_ms),
    "segment_restarted" => @position ++ ~w(elapsed_ms),
    # Round counter (audit U3) and check-off undo (U4)
    "round_incremented" => @position ++ ~w(round_count),
    "round_decremented" => @position ++ ~w(round_count),
    "check_off_undone" => @position,
    # On-the-fly adjust (audit U14)
    "time_adjusted" => @position ++ ~w(delta_seconds),
    "rounds_adjusted" => @position ++ ~w(delta_rounds round_count),
    # Ready screen + get-ready countdown, time-to-first-rep (audit U5, §1.3)
    "ready_screen_shown" => ~w(format surface),
    "workout_launched" => ~w(format surface countdown_seconds),
    "first_segment_started" => ~w(segment_index section_id format duration_ms),
    # Finish wizard drop-off (audit U2, U8, §1.3)
    "finish_wizard_opened" => ~w(surface segment_index),
    "finish_wizard_saved" => ~w(step duration_ms scored_section_count),
    "finish_wizard_abandoned" => ~w(step duration_ms),
    # Landscape / cast mode (audit U13) and cue toggles (U1)
    "cast_mode_toggled" => ~w(enabled orientation surface),
    "cues_toggled" => ~w(enabled cue_channel surface)
  }

  @uuid ~r/\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
  @token ~r/\A[A-Za-z0-9_\-]{1,64}\z/

  def kinds, do: @kinds_fields |> Map.keys() |> Enum.sort()
  def fields, do: @fields |> Map.keys() |> Enum.sort()
  def max_batch, do: @max_batch
  def allowed_fields(kind), do: Map.get(@kinds_fields, kind, [])

  @doc """
  Validates a batch. Returns `{:ok, [normalized]}` or
  `{:error, {:invalid_execution_interactions, [%{index: i, reason: atom}]}}`.
  The whole batch is rejected when any event is invalid.
  """
  def validate_batch(events, %DateTime{} = now) when is_list(events) do
    cond do
      events == [] ->
        {:error, {:invalid_execution_interactions, [%{index: 0, reason: :empty_batch}]}}

      length(events) > @max_batch ->
        {:error, {:invalid_execution_interactions, [%{index: 0, reason: :batch_too_large}]}}

      true ->
        events
        |> Enum.with_index()
        |> Enum.map(fn {event, index} -> {index, validate(event, now)} end)
        |> collect()
    end
  end

  def validate_batch(_events, _now),
    do: {:error, {:invalid_execution_interactions, [%{index: 0, reason: :invalid_batch}]}}

  defp collect(results) do
    case Enum.filter(results, fn {_index, result} -> match?({:error, _}, result) end) do
      [] ->
        {:ok, results |> Enum.map(fn {_index, {:ok, event}} -> event end) |> uniq_by_client_id()}

      errors ->
        {:error,
         {:invalid_execution_interactions,
          Enum.map(errors, fn {index, {:error, reason}} -> %{index: index, reason: reason} end)}}
    end
  end

  # Duplicates inside one batch collapse before reaching storage.
  defp uniq_by_client_id(events), do: Enum.uniq_by(events, & &1.client_event_id)

  defp validate(event, now) when is_map(event) do
    with {:ok, client_event_id} <- client_event_id(value(event, "client_event_id")),
         {:ok, kind} <- kind(value(event, "kind")),
         {:ok, occurred_at} <- occurred_at(value(event, "occurred_at"), now),
         {:ok, metadata} <- metadata(kind, value(event, "metadata") || %{}) do
      {:ok,
       %{
         client_event_id: String.downcase(client_event_id),
         kind: kind,
         occurred_at: occurred_at,
         metadata: metadata
       }}
    end
  end

  defp validate(_event, _now), do: {:error, :invalid_event}

  defp client_event_id(id) when is_binary(id) do
    if Regex.match?(@uuid, id), do: {:ok, id}, else: {:error, :invalid_client_event_id}
  end

  defp client_event_id(_id), do: {:error, :invalid_client_event_id}

  defp kind(kind) when is_binary(kind) do
    if Map.has_key?(@kinds_fields, kind), do: {:ok, kind}, else: {:error, :unknown_kind}
  end

  defp kind(_kind), do: {:error, :unknown_kind}

  defp occurred_at(%DateTime{} = at, now), do: within_window(at, now)

  defp occurred_at(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> within_window(at, now)
      _error -> {:error, :invalid_occurred_at}
    end
  end

  defp occurred_at(_value, _now), do: {:error, :invalid_occurred_at}

  defp within_window(at, now) do
    diff = DateTime.diff(now, at, :second)

    cond do
      diff > @max_age_seconds -> {:error, :occurred_at_out_of_range}
      diff < -@max_skew_seconds -> {:error, :occurred_at_out_of_range}
      true -> {:ok, usec(at)}
    end
  end

  # analytics_events.occurred_at is utc_datetime_usec.
  defp usec(%DateTime{microsecond: {value, _precision}} = at),
    do: %{at | microsecond: {value, 6}}

  defp metadata(kind, metadata) when is_map(metadata) do
    allowed = Map.fetch!(@kinds_fields, kind)

    Enum.reduce_while(metadata, {:ok, %{}}, fn {key, raw}, {:ok, acc} ->
      key = to_string(key)

      cond do
        key not in allowed -> {:halt, {:error, :metadata_field_not_allowed}}
        is_nil(raw) -> {:cont, {:ok, acc}}
        true -> typed(key, raw, acc)
      end
    end)
  end

  defp metadata(_kind, _metadata), do: {:error, :invalid_metadata}

  defp typed(key, raw, acc) do
    if valid_value?(Map.fetch!(@fields, key), raw),
      do: {:cont, {:ok, Map.put(acc, key, raw)}},
      else: {:halt, {:error, :invalid_metadata_value}}
  end

  defp valid_value?({:integer, min, max}, value),
    do: is_integer(value) and value >= min and value <= max

  defp valid_value?({:enum, values}, value), do: is_binary(value) and value in values
  defp valid_value?(:boolean, value), do: is_boolean(value)
  defp valid_value?(:token, value), do: is_binary(value) and Regex.match?(@token, value)

  @atom_keys %{
    "client_event_id" => :client_event_id,
    "kind" => :kind,
    "occurred_at" => :occurred_at,
    "metadata" => :metadata
  }

  defp value(map, key), do: Map.get(map, key, Map.get(map, Map.fetch!(@atom_keys, key)))
end
