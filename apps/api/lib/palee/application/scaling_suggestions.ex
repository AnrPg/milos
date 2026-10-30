defmodule Palee.Application.ScalingSuggestions do
  @moduledoc """
  AI scaling suggestions (ADR-174): the scan, the advisor call, the coach's
  approval queue and the member's read.

  * **Off by default.** Nothing runs unless the gym switched scaling on in
    its AI settings and gave its own key (`AiUsage.scaling_ready?/1`).
  * **Only when needed.** The hourly scan looks at assignments of the next
    two days and calls the advisor only for an athlete whose gym-provenance
    injuries the deterministic policy (ADR-124) flags on that workout; a
    personal self-report never leaves the member's account.
  * **Coach approval is mandatory.** A suggestion lands as `pending` in the
    queue of the coaches who may manage the athlete's coaching and see their
    health data; only `approve/4` makes it `approved`, and the member reads
    nothing else (`for_member/3`).
  * **Metered.** Every call is recorded per gym in `ai_usage_records`
    (feature `scaling_suggestions`, ADR-152).
  """

  require Logger

  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Workers.GenerateScalingSuggestionJob
  alias Palee.{AiUsage, Execution, Identity, Organizations, Scaling, Wellbeing, Workouts}

  @feature "scaling_suggestions"
  @history 5

  def feature, do: @feature

  # ── Scan ──────────────────────────────────────────────────────────────

  @doc "The hourly scan over every active gym (errors in one gym never stop the others)."
  def scan_all(today \\ Date.utc_today()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      try do
        with {:ok, context} <-
               Organizations.resolve_system_tenant_context(organization.id, :scaling_suggestions) do
          scan(context, today)
        end
      rescue
        error ->
          Logger.error(
            "scaling_scan_failed organization_id=#{organization.id} #{Exception.message(error)}"
          )
      end
    end)
  end

  @doc """
  One gym's scan: queues a generation for every athlete with a flagged
  movement in an assignment of the window. Returns the queued pairs.
  """
  def scan(context, today) do
    if ready?(context) do
      context
      |> candidates(today)
      |> Enum.map(fn {assignment, athlete_id, _warnings} ->
        enqueue(context, assignment.id, athlete_id, today)
        {assignment.id, athlete_id}
      end)
    else
      []
    end
  end

  defp candidates(context, today) do
    {from, to} = Scaling.scan_window(today)
    assignments = Workouts.list_assigned_workouts_for_admin(context, from, to)
    athlete_ids = assignments |> Enum.flat_map(& &1.athlete_ids) |> Enum.uniq()

    injuries =
      if athlete_ids == [],
        do: %{},
        else:
          context
          |> Wellbeing.with_tenant_context(fn ->
            Wellbeing.list_active_injuries_for_users(athlete_ids)
          end)
          # ADR-286: a member's own shared reports inform the coach, never
          # the AI advisor, which reads the gym's records only.
          |> Enum.reject(&is_nil(&1.organization_id))
          |> Enum.group_by(& &1.user_id)

    for assignment <- assignments,
        athlete_id <- assignment.athlete_ids,
        athlete_injuries = Map.get(injuries, athlete_id, []),
        athlete_injuries != [],
        warnings = flagged_warnings(athlete_injuries, assignment.workout),
        warnings != [] do
      {assignment, athlete_id, {athlete_injuries, warnings}}
    end
  end

  defp flagged_warnings(injuries, workout) do
    injuries
    |> Wellbeing.evaluate_injury_risk(Workouts.exercise_descriptors(workout))
    |> Map.get(:warnings, [])
    |> Enum.filter(&(&1.exercises != []))
  end

  defp enqueue(%{organization_id: organization_id} = context, assignment_id, athlete_id, today) do
    if Application.get_env(:palee, :start_oban, true) do
      %{
        "organization_id" => organization_id,
        "assignment_id" => assignment_id,
        "athlete_id" => athlete_id
      }
      |> GenerateScalingSuggestionJob.new()
      |> Oban.insert()
    else
      generate(context, assignment_id, athlete_id, today)
    end
  end

  # ── Generate ──────────────────────────────────────────────────────────

  @doc """
  Asks the advisor for one athlete's assignment, unless the latest live
  suggestion already answers the same inputs or the coach decided on it.
  Returns `{:ok, suggestion}`, `{:ok, :skipped}`, or `{:error, reason}`:
  `:scaling_disabled` and `:not_needed` are final, provider errors may retry.
  """
  def generate(context, assignment_id, athlete_id, today \\ Date.utc_today()) do
    with {:ok, settings} <- ready_settings(context),
         {:ok, assignment, injuries, warnings} <-
           candidate(context, assignment_id, athlete_id, today) do
      input =
        Scaling.build_input(%{
          workout: assignment.workout,
          injuries: injuries,
          warnings: warnings,
          scale_levels: Workouts.list_scale_levels(context),
          history: Scaling.approved_history(context, athlete_id, @history),
          locale: locale(context)
        })

      digest = Scaling.digest(input)

      case Scaling.next_step(Scaling.latest_live(context, assignment_id, athlete_id), digest) do
        :skip ->
          {:ok, :skipped}

        :generate ->
          ask(context, settings, assignment, athlete_id, input, digest, warnings, nil)

        {:replace, latest} ->
          ask(context, settings, assignment, athlete_id, input, digest, warnings, latest)
      end
    end
  end

  defp candidate(context, assignment_id, athlete_id, today) do
    context
    |> candidates(today)
    |> Enum.find(fn {assignment, candidate_id, _found} ->
      assignment.id == assignment_id and candidate_id == athlete_id
    end)
    |> case do
      {assignment, _athlete_id, {injuries, warnings}} -> {:ok, assignment, injuries, warnings}
      nil -> {:error, :not_needed}
    end
  end

  defp ask(context, settings, assignment, athlete_id, input, digest, warnings, previous) do
    operation_id = Ecto.UUID.generate()
    model = AiUsage.settings_model(settings, Scaling.default_model())

    options = %{
      api_key: settings.api_key,
      model: model,
      metering: %{
        operation_id: operation_id,
        feature: @feature,
        organization_id: context.organization_id,
        user_id: nil
      }
    }

    movements = Scaling.movements(assignment.workout)

    with {:ok, raw} <- advise(context, input, options),
         {:ok, advice} <- Scaling.normalize_advice(raw, movements, input.scale_levels) do
      attrs =
        advice_attrs(advice)
        |> Map.merge(%{
          athlete_id: athlete_id,
          assigned_workout_id: assignment.id,
          master_workout_id: assignment.workout.id,
          scheduled_for: Date.from_iso8601!(assignment.scheduled_for),
          injury_regions: Scaling.injury_regions(warnings),
          input_digest: digest,
          provider: "anthropic",
          model: model,
          operation_id: operation_id
        })

      if previous,
        do: Scaling.replace(context, previous, attrs),
        else: Scaling.insert(context, attrs)
    end
  end

  defp advice_attrs(:no_change), do: %{status: "no_change", items: []}

  defp advice_attrs(advice),
    do: %{
      status: "pending",
      summary: advice.summary,
      scale_level_slug: advice.scale_level_slug,
      items: advice.items
    }

  defp advise(context, input, options) do
    case Scaling.suggest(input, options) do
      {:error, :advisor_key_rejected} = error ->
        _ =
          AiUsage.put_settings(context, %{
            key_status: "rejected",
            key_checked_at: DateTime.utc_now()
          })

        error

      {:ok, raw} ->
        mark_key_valid(context)
        {:ok, raw}

      error ->
        error
    end
  end

  defp mark_key_valid(context) do
    case AiUsage.get_settings(context) do
      %{key_status: "valid"} ->
        :ok

      _other ->
        AiUsage.put_settings(context, %{key_status: "valid", key_checked_at: DateTime.utc_now()})
    end
  end

  defp ready?(context), do: match?({:ok, _settings}, ready_settings(context))

  defp ready_settings(context) do
    settings = AiUsage.get_settings(context)
    if AiUsage.scaling_ready?(settings), do: {:ok, settings}, else: {:error, :scaling_disabled}
  end

  defp locale(%{organization_id: organization_id}) do
    case Organizations.get_organization_settings(organization_id) do
      %{default_locale: locale} when is_binary(locale) -> locale
      _none -> "el"
    end
  end

  # ── Coach queue ───────────────────────────────────────────────────────

  @doc """
  The coach's queue: suggestions for athletes the actor may manage
  (`manage_coaching`) and whose health data they may see (`view_health`),
  pending by default, from today on.
  """
  def queue(context, params \\ %{}, today \\ Date.utc_today()) do
    case reachable_athletes(context) do
      [] ->
        []

      athlete_ids ->
        context
        |> Scaling.list(%{
          status: Map.get(params, :status, "pending"),
          athlete_ids: athlete_ids,
          from: today
        })
        |> present(context)
    end
  end

  defp reachable_athletes(context) do
    case {AuthorizeClientAccess.client_ids(context, :manage_coaching),
          AuthorizeClientAccess.client_ids(context, :view_health)} do
      {:all, :all} -> :all
      {:all, ids} -> ids
      {ids, :all} -> ids
      {left, right} -> Enum.filter(left, &(&1 in right))
    end
  end

  defp present(suggestions, context) do
    nicknames =
      suggestions
      |> Enum.map(& &1.athlete_id)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    titles = workout_titles(context, Enum.map(suggestions, & &1.master_workout_id))
    labels = scale_labels(context, suggestions)

    Enum.map(suggestions, fn suggestion ->
      suggestion
      |> view()
      |> Map.merge(%{
        athlete_nickname: Map.get(nicknames, suggestion.athlete_id),
        workout_title: Map.get(titles, suggestion.master_workout_id),
        scale_level_label: Map.get(labels, suggestion.scale_level_slug)
      })
    end)
  end

  # The gym's own names for its scale levels (ADR-128), read only when needed.
  defp scale_labels(context, suggestions) do
    if Enum.any?(suggestions, &is_binary(&1.scale_level_slug)),
      do: context |> Workouts.list_scale_levels() |> Map.new(&{&1.slug, &1.label}),
      else: %{}
  end

  defp workout_titles(_context, []), do: %{}

  defp workout_titles(context, ids) do
    ids
    |> Enum.uniq()
    |> Map.new(fn id ->
      case Workouts.get_workout_for_admin(context, id) do
        %{title: title} -> {id, title}
        _missing -> {id, nil}
      end
    end)
  end

  defp view(suggestion) do
    %{
      id: suggestion.id,
      athlete_id: suggestion.athlete_id,
      assigned_workout_id: suggestion.assigned_workout_id,
      master_workout_id: suggestion.master_workout_id,
      scheduled_for: suggestion.scheduled_for,
      status: suggestion.status,
      summary: suggestion.summary,
      scale_level_slug: suggestion.scale_level_slug,
      injury_regions: suggestion.injury_regions,
      items: Enum.map(suggestion.items, &item_view/1),
      coach_note: suggestion.coach_note,
      reviewed_at: suggestion.reviewed_at,
      inserted_at: suggestion.inserted_at
    }
  end

  defp item_view(item) do
    Map.new(
      ~w(id exercise_id section_id section_name exercise_name prescribed change suggested reason)a,
      fn key ->
        {key, Map.get(item, key, Map.get(item, to_string(key)))}
      end
    )
  end

  @doc "Approves a pending suggestion, with the coach's edits; it becomes modifications."
  def approve(context, id, params, now \\ DateTime.utc_now()) do
    with {:ok, suggestion} <- reviewable(context, id),
         {:ok, changes} <- Scaling.approve_changes(suggestion, params, context.user_id, now),
         :ok <- validate_patches(changes.modifications),
         {:ok, updated} <- Scaling.update(context, suggestion, changes) do
      {:ok, updated |> List.wrap() |> present(context) |> hd()}
    end
  end

  @doc "Dismisses a pending suggestion; nothing reaches the athlete."
  def dismiss(context, id, now \\ DateTime.utc_now()) do
    with {:ok, suggestion} <- reviewable(context, id),
         {:ok, changes} <- Scaling.dismiss_changes(suggestion, context.user_id, now),
         {:ok, updated} <- Scaling.update(context, suggestion, changes) do
      {:ok, updated |> List.wrap() |> present(context) |> hd()}
    end
  end

  defp reviewable(context, id) do
    with %{} = suggestion <- Scaling.get(context, id) || {:error, :not_found},
         :ok <- AuthorizeClientAccess.call(context, :manage_coaching, suggestion.athlete_id),
         :ok <- AuthorizeClientAccess.call(context, :view_health, suggestion.athlete_id) do
      {:ok, suggestion}
    else
      {:error, :not_your_client} -> {:error, :not_found}
      {:error, :forbidden} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ADR-050: every approved change must be a valid modification patch.
  defp validate_patches(patches) do
    if Enum.all?(patches, &match?({:ok, _patch}, Execution.normalize_modification(&1))),
      do: :ok,
      else: {:error, :invalid_modification}
  end

  # ── Member ────────────────────────────────────────────────────────────

  @doc """
  The acting member's approved adaptation of a workout (an assignment from
  yesterday on), or nil. Pending, dismissed and superseded suggestions are
  never returned.
  """
  def for_member(%{user_id: user_id} = context, workout_id, today \\ Date.utc_today()) do
    case Ecto.UUID.cast(workout_id) do
      {:ok, workout_id} ->
        context
        |> Scaling.approved_for_member(user_id, workout_id, Date.add(today, -1))
        |> case do
          nil ->
            {:ok, nil}

          suggestion ->
            label = Map.get(scale_labels(context, [suggestion]), suggestion.scale_level_slug)
            {:ok, suggestion |> Scaling.member_view() |> Map.put(:scale_level_label, label)}
        end

      :error ->
        {:error, :not_found}
    end
  end
end
