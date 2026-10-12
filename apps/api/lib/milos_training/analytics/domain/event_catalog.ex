defmodule MilosTraining.Analytics.Domain.EventCatalog do
  @moduledoc """
  Registry of every analytics event name the platform may record (ADR-015,
  ADR-113) and the pure builder that turns an application-boundary fact into
  an `analytics_events` row.

  The registry is the allowlist: `Analytics.record_event/1` refuses names that
  are not listed here, so a typo at a call site fails loudly in tests instead
  of silently creating a new event family. It deliberately lives here and not
  in a database check constraint, so adding an event type never needs a
  migration.

  Metadata is restricted to ids, enums, counts, booleans and dates: string
  values longer than #{64} characters are dropped, and maps/lists are never
  copied, so free text (titles, bodies, notes) cannot leak into analytics.
  """

  # Phase 8 (ADR-015) finance / feedback / wellbeing / notification events.
  @legacy_events %{
    "payment_recorded" => "finance_payment",
    "promotion_redeemed" => "finance_promotion",
    "referral_event_created" => "finance_referral",
    "referral_status_changed" => "finance_referral",
    "referral_reward_created" => "finance_referral_reward",
    "referral_reward_status_changed" => "finance_referral_reward",
    "finance_invoice_created" => "finance_invoice",
    "finance_invoice_issued" => "finance_invoice",
    "finance_invoice_voided" => "finance_invoice",
    "finance_renewal_invoice_generated" => "finance_invoice",
    "finance_receipt_issued" => "finance_receipt",
    "finance_payment_reversed" => "finance_payment",
    "finance_credit_granted" => "finance_credit",
    "finance_credit_applied_to_invoice" => "finance_credit",
    "finance_credit_applied_to_payment" => "finance_credit",
    "finance_credit_reversed" => "finance_credit",
    "finance_record_soft_deleted" => "finance_record",
    "review_submitted" => "review",
    "injury_reported" => "injury",
    "injury_healed" => "injury",
    "notification_read" => "notification",
    "notification_clicked" => "notification"
  }

  # ADR-113 instrumentation. Each entry: context_type, the subject keys copied
  # into metadata, and the dedupe strategy.
  #
  #   dedupe: nil            - every occurrence is recorded
  #           :subject       - once per subject id (retries / replays collapse)
  #           :user_subject_day - once per actor, subject and UTC day
  #           :explicit      - the caller supplies `dedupe_key` (namespaced)
  @instrumented_events %{
    # Workouts
    "workout_created" => {"workout", [:status, :type, :authoring_mode], nil},
    "workout_published" =>
      {"workout", [:type, :authoring_mode, :is_team_workout, :source_workout_id], nil},
    "workout_republished" =>
      {"workout", [:type, :authoring_mode, :is_team_workout, :source_workout_id], nil},
    "workout_deleted" => {"workout", [], nil},
    "workout_duplicated" => {"workout", [:source_workout_id, :type, :authoring_mode], nil},
    "workout_assignment_created" =>
      {"assigned_workout", [:master_workout_id, :scheduled_for], nil},
    "workout_assignment_rescheduled" =>
      {"assigned_workout", [:master_workout_id, :scheduled_for], nil},
    "workout_assignment_rejected" => {"assigned_workout", [:master_workout_id], nil},
    "workout_assignment_deleted" => {"assigned_workout", [:master_workout_id], nil},
    "workout_assignment_opened" =>
      {"assigned_workout", [:master_workout_id, :scheduled_for], :user_subject_day},
    # Execution
    "workout_execution_started" =>
      {"workout_execution", [:master_workout_id, :source, :scale_level_slug], :subject},
    "workout_execution_completed" =>
      {"workout_execution", [:master_workout_id, :source, :scale_level_slug], :subject},
    "workout_execution_abandoned" =>
      {"workout_execution", [:master_workout_id, :source, :scale_level_slug, :status], :subject},
    "execution_interaction" => {"workout_execution", [], :explicit},
    "training_log_entry_logged" =>
      {"training_log_entry",
       [
         :source_type,
         :master_workout_id,
         :workout_type,
         :scale_level_slug,
         :duration_seconds,
         :perceived_effort
       ], :subject},
    "training_log_entry_voided" => {"training_log_entry", [:source_type], :subject},
    # Scheduling
    "class_booking_requested" => {"class_booking", [:scheduled_class_id, :status], :subject},
    "class_booking_approved" => {"class_booking", [:scheduled_class_id], :subject},
    "class_booking_rejected" => {"class_booking", [:scheduled_class_id], :subject},
    "class_booking_cancelled" => {"class_booking", [:scheduled_class_id], :subject},
    "class_booking_timed_out" => {"class_booking", [:scheduled_class_id], :subject},
    "class_attendance_recorded" =>
      {"class_attendance", [:scheduled_class_id, :booking_id, :status], nil},
    "class_slot_created" =>
      {"scheduled_class",
       [:class_type_id, :master_workout_id, :capacity, :auto_approve, :series_id], nil},
    "class_series_created" => {"class_series", [:class_type_id, :master_workout_id], nil},
    "class_slot_cancelled" => {"scheduled_class", [], nil},
    # Messaging
    "messaging_thread_created" => {"messaging_thread", [:context_type], :subject},
    "messaging_message_sent" => {"messaging_message", [:thread_id, :message_type], :subject},
    "messaging_first_staff_response" =>
      {"messaging_message", [:thread_id, :message_type], :subject},
    # Notifications
    "notification_in_app_delivered" => {"notification", [:type], :subject},
    "notification_push_outcome" => {"notification", [], nil},
    # Wellbeing safety warnings (ADR-114). context_id is the workout.
    "injury_warning_shown" => {"workout", [], :explicit},
    "injury_warning_acknowledged" => {"workout", [], :explicit}
  }

  # ADR-114: health-adjacent events keep ONLY these metadata keys - enums,
  # counts and ids. Body areas, limitations, tags and any other free text are
  # dropped even when short enough to pass `sanitize/1`.
  @injury_warning_metadata_keys ~w(
    audience surface warning_level injury_warning_count avoid_exercise_count
    caution_exercise_count athlete_id source_context_id
  )
  @metadata_allowlists %{
    "injury_warning_shown" => @injury_warning_metadata_keys,
    "injury_warning_acknowledged" => @injury_warning_metadata_keys
  }

  # ADR-114 segmentation facts added to `workout_execution_completed`:
  # booleans/enums derived from organization-provenance injuries only.
  @injury_segmentation_keys ~w(had_active_injury injury_warning_level)

  @max_string_length 64

  @doc "Every registered event name, sorted."
  def event_names do
    (Map.keys(@legacy_events) ++ Map.keys(@instrumented_events)) |> Enum.sort()
  end

  @doc "Event names added by ADR-113 instrumentation, sorted."
  def instrumented_event_names, do: @instrumented_events |> Map.keys() |> Enum.sort()

  @doc "Metadata keys allowed for the ADR-114 injury warning events."
  def injury_warning_metadata_keys, do: @injury_warning_metadata_keys

  @doc "ADR-114 injury segmentation keys carried by execution completion facts."
  def injury_segmentation_keys, do: @injury_segmentation_keys

  def registered?(name) when is_binary(name),
    do: Map.has_key?(@legacy_events, name) or Map.has_key?(@instrumented_events, name)

  def registered?(_name), do: false

  @doc """
  Builds the attrs for an `analytics_events` row.

  * `actor` - the acting tenant context (or any map with `:organization_id`,
    `:user_id`, `:role`), or `nil` for system/job facts.
  * `subject` - the result of the primary operation (struct or map); its `:id`
    becomes `context_id` and its listed keys are copied into metadata.
  * `extra` - `:metadata` (merged over the subject keys), `:occurred_at`
    (`DateTime`, required for `:user_subject_day` dedupe), and optional
    overrides `:organization_id`, `:user_id`, `:context_id`, `:dedupe_key`.
  """
  def build(event_name, actor, subject, extra \\ %{}) do
    case spec(event_name) do
      nil ->
        {:error, :unknown_analytics_event}

      {context_type, subject_keys, dedupe} ->
        actor = actor || %{}
        subject = subject || %{}
        context_id = field(extra, :context_id) || field(subject, :id)
        user_id = field(extra, :user_id) || field(actor, :user_id)
        occurred_at = field(extra, :occurred_at)

        attrs =
          %{
            event_name: event_name,
            organization_id:
              field(extra, :organization_id) || field(actor, :organization_id) ||
                field(subject, :organization_id),
            user_id: user_id,
            actor_role_snapshot: role(actor),
            context_type: context_type,
            context_id: context_id,
            occurred_at: occurred_at,
            metadata:
              subject
              |> take(subject_keys)
              |> Map.merge(sanitize(field(extra, :metadata) || %{}))
              |> allowlist(event_name),
            dedupe_key: dedupe_key(dedupe, event_name, user_id, context_id, occurred_at, extra)
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()

        {:ok, attrs}
    end
  end

  @doc "Keeps only scalar, bounded metadata values; drops maps, lists and long strings."
  def sanitize(metadata) when is_map(metadata) do
    metadata
    |> Enum.flat_map(fn {key, value} ->
      case scalar(value) do
        {:ok, scalar} -> [{to_string(key), scalar}]
        :drop -> []
      end
    end)
    |> Map.new()
  end

  def sanitize(_metadata), do: %{}

  defp spec(name) do
    case Map.fetch(@instrumented_events, name) do
      {:ok, spec} ->
        spec

      :error ->
        case Map.fetch(@legacy_events, name) do
          {:ok, context_type} -> {context_type, [], nil}
          :error -> nil
        end
    end
  end

  defp allowlist(metadata, event_name) do
    case Map.fetch(@metadata_allowlists, event_name) do
      {:ok, keys} -> Map.take(metadata, keys)
      :error -> metadata
    end
  end

  defp take(subject, keys) do
    keys
    |> Map.new(fn key -> {key, field(subject, key)} end)
    |> sanitize()
  end

  defp dedupe_key(nil, _event, _user_id, _context_id, _occurred_at, _extra), do: nil
  defp dedupe_key(_strategy, _event, _user_id, nil, _occurred_at, _extra), do: nil

  defp dedupe_key(:subject, _event, _user_id, context_id, _occurred_at, _extra),
    do: to_string(context_id)

  defp dedupe_key(:user_subject_day, _event, user_id, context_id, %DateTime{} = at, _extra)
       when is_binary(user_id),
       do: "#{user_id}:#{context_id}:#{Date.to_iso8601(DateTime.to_date(at))}"

  defp dedupe_key(:user_subject_day, _event, _user_id, _context_id, _occurred_at, _extra),
    do: nil

  defp dedupe_key(:explicit, _event, _user_id, _context_id, _occurred_at, extra) do
    case field(extra, :dedupe_key) do
      key when is_binary(key) and byte_size(key) <= 255 -> key
      _missing -> nil
    end
  end

  defp scalar(nil), do: :drop
  defp scalar(value) when is_boolean(value), do: {:ok, value}
  defp scalar(value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp scalar(value) when is_integer(value), do: {:ok, value}
  defp scalar(value) when is_float(value), do: {:ok, value}
  defp scalar(%Date{} = value), do: {:ok, Date.to_iso8601(value)}
  defp scalar(%DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}

  defp scalar(value) when is_binary(value) do
    if String.length(value) <= @max_string_length, do: {:ok, value}, else: :drop
  end

  defp scalar(_value), do: :drop

  defp role(%{role: role}) when is_atom(role) and not is_nil(role), do: Atom.to_string(role)
  defp role(%{role: role}) when is_binary(role), do: role
  defp role(_actor), do: nil

  defp field(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      value -> value
    end
  end

  defp field(_map, _key), do: nil
end
