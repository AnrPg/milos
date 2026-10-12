defmodule MilosTraining.Execution.Domain.TrainingLogPolicy do
  @moduledoc """
  Pure rules for standalone training-log entries (ADR-108).

  The policy normalizes user-entered training details, decides whether a
  source may be logged without double counting an execution, and projects a
  logged entry into the completion-record shape the gamification projection
  already consumes for executions. Callers pass `now` explicitly so the
  module stays deterministic.
  """

  alias MilosTraining.Execution.Domain.ModificationPatchValidator

  @source_types ~w(class assigned_workout library_workout freeform)
  @future_tolerance_seconds 15 * 60
  @max_age_days 366
  @max_duration_seconds 24 * 60 * 60
  @max_performed_exercises 50
  @max_section_scores 50
  @load_units ~w(kg lb)
  @distance_units ~w(m km mi)
  @disqualifying_attendance ~w(missed cancelled late_cancel no_show)

  @type source :: %{
          required(:source_type) => String.t(),
          optional(:source_reference_id) => String.t() | nil,
          optional(:booking_id) => String.t() | nil,
          optional(:master_workout_id) => String.t() | nil
        }

  def source_types, do: @source_types

  def normalize_source_type(value) when value in @source_types, do: {:ok, value}

  def normalize_source_type(value) when is_atom(value) and not is_nil(value),
    do: value |> Atom.to_string() |> normalize_source_type()

  def normalize_source_type(_value), do: {:error, :invalid_training_log_source}

  @doc """
  Normalizes the user-editable details of an entry.

  `mode` is `:create` (performed_at required, defaults applied) or `:update`
  (only keys present in `params` are returned). `opts`:

    * `:now` - reference time (required)
    * `:structured?` - whether the source has a canonical workout, which
      enables ADR-050 modification patches
    * `:allowed_section_ids` - scoreable section ids of the source workout
    * `:freeform?` - whether the title is user-provided
  """
  def normalize_details(params, opts, mode \\ :create)

  def normalize_details(params, opts, mode) when is_map(params) do
    now = Keyword.fetch!(opts, :now)

    steps = [
      {:performed_at_utc, "performed_at", &normalize_performed_at(&1, now)},
      {:performed_at_tz, "timezone", &normalize_timezone/1},
      {:duration_seconds, "duration_seconds", &normalize_duration/1},
      {:perceived_effort, "perceived_effort", &normalize_effort/1},
      {:notes, "notes", &normalize_notes/1},
      {:scale_level_slug, "scale_level_slug", &normalize_scale/1},
      {:section_scores, "section_scores",
       &normalize_section_scores(&1, Keyword.get(opts, :allowed_section_ids, []))},
      {:exercise_modifications, "exercise_modifications",
       &normalize_modifications(&1, Keyword.get(opts, :structured?, false))},
      {:performed_exercises, "performed_exercises", &normalize_performed_exercises/1}
    ]

    steps =
      if Keyword.get(opts, :freeform?, false),
        do: [{:title, "title", &normalize_title/1} | steps],
        else: steps

    steps
    |> Enum.reduce_while({:ok, %{}}, fn {field, key, normalizer}, {:ok, acc} ->
      case fetch(params, key) do
        :missing when mode == :update ->
          {:cont, {:ok, acc}}

        :missing ->
          apply_normalizer(normalizer, nil, field, acc)

        {:ok, value} ->
          apply_normalizer(normalizer, value, field, acc)
      end
    end)
  end

  def normalize_details(_params, _opts, _mode), do: {:error, [base: "is invalid"]}

  defp apply_normalizer(normalizer, value, field, acc) do
    case normalizer.(value) do
      {:ok, normalized} -> {:cont, {:ok, Map.put(acc, field, normalized)}}
      {:error, message} -> {:halt, {:error, [{field, message}]}}
    end
  end

  @doc """
  ADR-110 replay rule for a reused `idempotency_key`.

  A replay converges on the original entry only when it names the same source
  (type and reference). Reusing a key for a different source is a
  deterministic `:idempotency_key_conflict` instead of silently returning an
  unrelated entry. `request` may be raw client params (string or atom keys)
  or a server-derived source map.
  """
  def replay_decision(entry, request) when is_map(entry) and is_map(request) do
    requested_type = request_value(request, :source_type)
    requested_reference = request_value(request, :source_reference_id)

    if to_string(entry.source_type) == requested_type and
         blank_to_nil(entry.source_reference_id) == requested_reference,
       do: :replay,
       else: {:error, :idempotency_key_conflict}
  end

  defp request_value(request, key) do
    value = Map.get(request, key, Map.get(request, Atom.to_string(key)))
    value |> blank_to_nil() |> then(&(&1 && to_string(&1)))
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Whether logging `source` would double count a completed execution.

  Class and assignment sources are counted once per relationship. A library
  workout may be repeated, so it only conflicts with a completed execution of
  the same workout on the same calendar day as the logged performance.
  """
  def double_counted?(%{source_type: "freeform"}, _executions, _performed_at), do: false

  def double_counted?(%{source_type: "class", booking_id: booking_id}, executions, _performed_at)
      when is_binary(booking_id) do
    Enum.any?(completed(executions), fn execution ->
      to_string(execution[:source]) == "class_booking" and
        execution[:source_reference_id] == booking_id
    end)
  end

  def double_counted?(
        %{source_type: "assigned_workout", source_reference_id: assignment_id},
        executions,
        _performed_at
      ) do
    Enum.any?(completed(executions), fn execution ->
      to_string(execution[:source]) == "assigned" and
        execution[:source_reference_id] == assignment_id
    end)
  end

  def double_counted?(
        %{source_type: "library_workout", master_workout_id: workout_id},
        executions,
        %DateTime{} = performed_at
      ) do
    performed_date = DateTime.to_date(performed_at)

    Enum.any?(completed(executions), fn execution ->
      execution[:master_workout_id] == workout_id and
        DateTime.to_date(execution.completed_at_utc) == performed_date
    end)
  end

  def double_counted?(_source, _executions, _performed_at), do: false

  @doc """
  Filters source-picker candidates down to the ones that can still be logged:
  not already logged (live entry) and not already counted by a completed
  execution. Each candidate carries `source_type`, `id` (the reference id) and
  optionally `booking_id`.
  """
  def loggable_candidates(candidates, logged_reference_ids, executions) do
    logged = MapSet.new(logged_reference_ids)

    Enum.reject(candidates, fn candidate ->
      source = %{
        source_type: candidate.source_type,
        source_reference_id: candidate.id,
        booking_id: candidate[:booking_id]
      }

      MapSet.member?(logged, candidate.id) or double_counted?(source, executions, nil)
    end)
  end

  defp completed(executions) do
    Enum.filter(executions, fn execution ->
      match?(%DateTime{}, execution[:completed_at_utc])
    end)
  end

  @doc """
  Decides whether a class may be logged by the member.

  `access` carries the slot plus the member's booking and attendance as seen
  through the Scheduling public API. An explicit non-attendance mark always
  wins; otherwise an `attended` mark or an approved booking qualifies once the
  class has started.
  """
  def authorize_class(%{slot: nil}, _now), do: {:error, :not_found}

  def authorize_class(%{slot: slot} = access, %DateTime{} = now) do
    attendance_status = access[:attendance] && to_string(access.attendance.status)
    booking_status = access[:booking] && to_string(access.booking.status)

    cond do
      DateTime.compare(slot.scheduled_at, now) == :gt ->
        {:error, :training_log_source_not_started}

      attendance_status in @disqualifying_attendance ->
        {:error, :training_log_source_forbidden}

      attendance_status == "attended" ->
        {:ok, access[:booking] && access.booking.id}

      booking_status == "approved" ->
        {:ok, access.booking.id}

      true ->
        {:error, :training_log_source_forbidden}
    end
  end

  @doc "Ensures `user_id` owns a live entry it wants to change."
  def ensure_editable(%{user_id: user_id, status: "logged"}, user_id), do: :ok

  def ensure_editable(%{user_id: user_id, status: "voided"}, user_id),
    do: {:error, :training_log_entry_voided}

  def ensure_editable(_entry, _user_id), do: {:error, :not_found}

  def void_attrs(reason, %DateTime{} = now) do
    case normalize_optional_text(reason, 500) do
      {:ok, normalized} -> {:ok, %{status: "voided", voided_at: now, void_reason: normalized}}
      {:error, message} -> {:error, [void_reason: message]}
    end
  end

  @doc """
  Projects a logged entry into the completion-record shape consumed by the
  gamification projection (`completed_at_utc`, `section_scores`, ...).

  Voided entries project to `nil` so they never count.
  """
  def completion_record(%{status: "voided"}), do: nil

  def completion_record(entry) do
    %{
      id: entry.id,
      user_id: entry.user_id,
      organization_id: entry.organization_id,
      master_workout_id: entry.master_workout_id,
      scale_level_slug: entry.scale_level_slug,
      source: "training_log",
      completion_source: "training_log",
      training_log_source_type: entry.source_type,
      source_reference_id: entry.source_reference_id,
      completed_at_utc: entry.performed_at_utc,
      completed_at_tz: entry.performed_at_tz,
      section_scores: entry.section_scores || [],
      exercise_modifications: entry.exercise_modifications || []
    }
  end

  @doc """
  Scoreable sections of a (flattened, normalized) workout, as offered to the
  log form. Their ids are the only `section_scores` targets accepted, which
  keeps PR detection meaningful for sourced entries.
  """
  def scoreable_sections(nil), do: []

  def scoreable_sections(%{sections: sections}) when is_list(sections) do
    sections
    |> Enum.filter(&(&1[:scoreable] == true))
    |> Enum.map(fn section ->
      config = section[:score_config] || %{}

      %{
        id: section.id,
        name: section[:name],
        score_type: to_string_or_nil(config[:type] || config["type"]),
        unit: config[:unit] || config["unit"]
      }
    end)
  end

  def scoreable_sections(_workout), do: []

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(value), do: to_string(value)

  def completion_records(entries) do
    entries
    |> Enum.map(&completion_record/1)
    |> Enum.reject(&is_nil/1)
  end

  # -- field normalizers ----------------------------------------------------

  defp normalize_performed_at(nil, _now), do: {:error, "can't be blank"}

  defp normalize_performed_at(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_performed_at(datetime, now)
      {:error, _reason} -> {:error, "is invalid"}
    end
  end

  defp normalize_performed_at(%DateTime{} = value, now) do
    value = DateTime.shift_zone!(value, "Etc/UTC")

    cond do
      DateTime.diff(value, now) > @future_tolerance_seconds ->
        {:error, "cannot be in the future"}

      DateTime.diff(now, value) > @max_age_days * 86_400 ->
        {:error, "is too far in the past"}

      true ->
        {:ok, value}
    end
  end

  defp normalize_performed_at(_value, _now), do: {:error, "is invalid"}

  defp normalize_timezone(nil), do: {:ok, "UTC"}

  defp normalize_timezone(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, "UTC"}
      trimmed when byte_size(trimmed) <= 64 -> {:ok, trimmed}
      _too_long -> {:error, "is invalid"}
    end
  end

  defp normalize_timezone(_value), do: {:error, "is invalid"}

  defp normalize_duration(nil), do: {:ok, nil}

  defp normalize_duration(value)
       when is_integer(value) and value >= 0 and value <= @max_duration_seconds,
       do: {:ok, value}

  defp normalize_duration(_value), do: {:error, "must be between 0 and 86400 seconds"}

  defp normalize_effort(nil), do: {:ok, nil}
  defp normalize_effort(value) when is_integer(value) and value in 1..10, do: {:ok, value}
  defp normalize_effort(_value), do: {:error, "must be between 1 and 10"}

  defp normalize_notes(value), do: normalize_optional_text(value, 4000)

  defp normalize_scale(nil), do: {:ok, nil}

  defp normalize_scale(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed when byte_size(trimmed) <= 64 -> {:ok, trimmed}
      _too_long -> {:error, "is invalid"}
    end
  end

  defp normalize_scale(_value), do: {:error, "is invalid"}

  defp normalize_title(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, "can't be blank"}
      trimmed when byte_size(trimmed) <= 160 -> {:ok, trimmed}
      _too_long -> {:error, "should be at most 160 character(s)"}
    end
  end

  defp normalize_title(_value), do: {:error, "can't be blank"}

  defp normalize_optional_text(nil, _max), do: {:ok, nil}

  defp normalize_optional_text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" ->
        {:ok, nil}

      trimmed ->
        if String.length(trimmed) <= max,
          do: {:ok, trimmed},
          else: {:error, "should be at most #{max} character(s)"}
    end
  end

  defp normalize_optional_text(_value, _max), do: {:error, "is invalid"}

  defp normalize_section_scores(nil, _allowed), do: {:ok, []}
  defp normalize_section_scores([], _allowed), do: {:ok, []}

  defp normalize_section_scores(scores, allowed)
       when is_list(scores) and length(scores) <= @max_section_scores do
    scores
    |> Enum.reduce_while({:ok, []}, fn score, {:ok, acc} ->
      case normalize_section_score(score, allowed) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, {:error, "contains an invalid score"}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, normalized |> Enum.reverse() |> Enum.uniq_by(& &1["section_id"])}
      error -> error
    end
  end

  defp normalize_section_scores(_scores, _allowed), do: {:error, "is invalid"}

  defp normalize_section_score(score, allowed) when is_map(score) do
    section_id = string_field(score, "section_id")
    value = raw_field(score, "value")
    unit = string_field(score, "unit")

    cond do
      is_nil(section_id) or section_id not in allowed -> :error
      not valid_score_value?(value) -> :error
      not is_nil(unit) and byte_size(unit) > 32 -> :error
      true -> {:ok, compact(%{"section_id" => section_id, "value" => value, "unit" => unit})}
    end
  end

  defp normalize_section_score(_score, _allowed), do: :error

  defp valid_score_value?(value) when is_number(value), do: value >= 0

  defp valid_score_value?(value) when is_binary(value),
    do: String.trim(value) != "" and byte_size(value) <= 64

  defp valid_score_value?(_value), do: false

  defp normalize_modifications(nil, _structured?), do: {:ok, []}
  defp normalize_modifications([], _structured?), do: {:ok, []}

  defp normalize_modifications(patches, true) when is_list(patches) do
    case ModificationPatchValidator.normalize_many(patches) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, _reason} -> {:error, "contains an invalid patch"}
    end
  end

  defp normalize_modifications(patches, false) when is_list(patches),
    do: {:error, "require a workout source"}

  defp normalize_modifications(_patches, _structured?), do: {:error, "is invalid"}

  defp normalize_performed_exercises(nil), do: {:ok, []}

  defp normalize_performed_exercises(rows)
       when is_list(rows) and length(rows) <= @max_performed_exercises do
    rows
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {row, index}, {:ok, acc} ->
      case normalize_performed_exercise(row, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        :error -> {:halt, {:error, "contains an invalid exercise"}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_performed_exercises(_rows), do: {:error, "is invalid"}

  defp normalize_performed_exercise(row, index) when is_map(row) do
    name = string_field(row, "name")

    with true <- is_binary(name) and String.length(name) <= 120,
         {:ok, exercise_ref} <- optional_string(row, "exercise_ref", 120),
         {:ok, sets} <- optional_int(row, "sets", 1, 100),
         {:ok, reps} <- optional_int(row, "reps", 0, 10_000),
         {:ok, load} <- optional_number(row, "load"),
         {:ok, load_unit} <- optional_enum(row, "load_unit", @load_units),
         {:ok, distance} <- optional_number(row, "distance"),
         {:ok, distance_unit} <- optional_enum(row, "distance_unit", @distance_units),
         {:ok, duration} <- optional_int(row, "duration_seconds", 0, @max_duration_seconds),
         {:ok, calories} <- optional_int(row, "calories", 0, 100_000),
         {:ok, note} <- optional_string(row, "note", 500) do
      {:ok,
       compact(%{
         "row_index" => index,
         "name" => name,
         "exercise_ref" => exercise_ref,
         "sets" => sets,
         "reps" => reps,
         "load" => load,
         "load_unit" => load_unit,
         "distance" => distance,
         "distance_unit" => distance_unit,
         "duration_seconds" => duration,
         "calories" => calories,
         "note" => note
       })}
    else
      _invalid -> :error
    end
  end

  defp normalize_performed_exercise(_row, _index), do: :error

  defp optional_string(map, key, max) do
    case raw_field(map, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:ok, nil}
          trimmed -> if String.length(trimmed) <= max, do: {:ok, trimmed}, else: :error
        end

      _other ->
        :error
    end
  end

  defp optional_int(map, key, min, max) do
    case raw_field(map, key) do
      nil -> {:ok, nil}
      value when is_integer(value) and value >= min and value <= max -> {:ok, value}
      _other -> :error
    end
  end

  defp optional_number(map, key) do
    case raw_field(map, key) do
      nil -> {:ok, nil}
      value when is_number(value) and value >= 0 and value <= 100_000 -> {:ok, value}
      _other -> :error
    end
  end

  defp optional_enum(map, key, allowed) do
    case raw_field(map, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> if value in allowed, do: {:ok, value}, else: :error
      _other -> :error
    end
  end

  defp string_field(map, key) do
    case raw_field(map, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _other ->
        nil
    end
  end

  defp raw_field(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> atom_field(map, key)
    end
  end

  defp atom_field(map, key) do
    Enum.find_value(map, fn
      {atom_key, value} when is_atom(atom_key) ->
        if Atom.to_string(atom_key) == key, do: value

      _other ->
        nil
    end)
  end

  defp fetch(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        Enum.find_value(params, :missing, fn
          {atom_key, value} when is_atom(atom_key) ->
            if Atom.to_string(atom_key) == key, do: {:ok, value}

          _other ->
            nil
        end)
    end
  end

  defp compact(map), do: map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
end
