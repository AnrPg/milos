defmodule Palee.Application.InjuryWarningEvaluation do
  @moduledoc """
  Shared orchestration for ADR-124 injury-aware workout safety warnings.

  Not a use case itself: the `*InjuryWarnings` application services call it so
  the visibility rules live in exactly one place.

    * Staff (`for_athletes/3`) only ever see injuries with the acting
      organization's provenance - never a member's personal self-reports,
      never another tenant's reports (`Wellbeing.list_active_injuries_for_users/1`).
    * The athlete/member (`for_self/2`) sees every own injury they may see,
      including personal self-reports, because they own them (ADR-055).
    * Analytics only ever reflect organization-provenance injuries of the
      acting tenant, so a personal injury never becomes a tenant-visible
      fact - not even as a boolean.

  Every DB read runs inside the caller's `RepoContext` session
  (`Wellbeing.with_tenant_context/2`). Warnings inform; nothing here blocks.
  """

  alias Palee.Application.TrackAnalyticsEvent
  alias Palee.{Analytics, Wellbeing, Workouts}

  @staff_surfaces ~w(assign_dialog class_roster member_dossier)
  @self_surfaces ~w(assignment_detail class_detail pre_start)

  def staff_surfaces, do: @staff_surfaces
  def self_surfaces, do: @self_surfaces

  @doc """
  Staff evaluation of `user_ids` against a published workout of the acting
  organization. Returns `{:ok, %{workout_id, level, athletes}}` with one entry
  per requested user (level `:none` when nothing applies).
  """
  def for_athletes(%{organization_id: organization_id} = context, workout_id, user_ids)
      when is_binary(organization_id) do
    user_ids = normalize_user_ids(user_ids)

    context
    |> Wellbeing.with_tenant_context(fn ->
      with {:ok, workout} <- fetch_workout(context, workout_id) do
        injuries = Wellbeing.list_active_injuries_for_users(user_ids)
        {:ok, workout, injuries}
      end
    end)
    |> case do
      {:ok, workout, injuries} ->
        exercises = Workouts.exercise_descriptors(workout)
        by_user = Enum.group_by(injuries, & &1.user_id)

        athletes =
          Enum.map(user_ids, fn user_id ->
            evaluation = Wellbeing.evaluate_injury_risk(Map.get(by_user, user_id, []), exercises)
            %{user_id: user_id, level: evaluation.level, warnings: evaluation.warnings}
          end)

        {:ok,
         %{
           workout_id: workout.id,
           level: Wellbeing.max_injury_warning_level(Enum.map(athletes, & &1.level)),
           athletes: athletes
         }}

      {:error, _reason} = error ->
        error
    end
  end

  def for_athletes(_context, _workout_id, _user_ids),
    do: {:error, :organization_context_required}

  @doc """
  The acting user's own evaluation for a published workout of the acting
  organization. Returns `{:ok, result, tenant_evaluation}` where
  `tenant_evaluation` only covers this organization's injuries (for
  analytics).

  Options: `scale:` - the scale level slug the athlete will run (TD-088).
  The exercises of that scale are evaluated: excluded movements drop out and
  substituted ones are matched by their own name. `nil` evaluates Rx.
  """
  def for_self(context, workout_id, opts \\ [])

  def for_self(%{organization_id: organization_id, user_id: user_id} = context, workout_id, opts)
      when is_binary(organization_id) and is_binary(user_id) do
    scale = scale_slug(Keyword.get(opts, :scale))

    context
    |> Wellbeing.with_tenant_context(fn ->
      with {:ok, workout} <- fetch_workout(context, workout_id) do
        {:ok, workout, Wellbeing.list_active_injuries_for_user(user_id)}
      end
    end)
    |> case do
      {:ok, workout, injuries} ->
        exercises = Workouts.exercise_descriptors(workout, scale)
        evaluation = Wellbeing.evaluate_injury_risk(injuries, exercises)

        tenant_evaluation =
          injuries
          |> Enum.filter(&(&1.organization_id == organization_id))
          |> Wellbeing.evaluate_injury_risk(exercises)

        {:ok,
         %{
           workout_id: workout.id,
           scale_level_slug: scale,
           level: evaluation.level,
           warnings: evaluation.warnings
         }, tenant_evaluation}

      {:error, _reason} = error ->
        error
    end
  end

  def for_self(_context, _workout_id, _opts), do: {:error, :organization_context_required}

  @doc """
  ADR-124 completion segmentation facts for a finished execution: whether the
  user had an active injury on record with the execution's organization, and
  the warning level that injury set implies for the workout. Organization
  provenance only - personal injuries never reach tenant analytics. Best
  effort: any failure yields `%{}`.
  """
  def completion_facts(%{organization_id: organization_id, user_id: user_id}, workout)
      when is_binary(organization_id) and is_binary(user_id) do
    %{organization_id: organization_id, user_id: user_id}
    |> Wellbeing.with_tenant_context(fn -> Wellbeing.list_active_injuries_for_user(user_id) end)
    |> case do
      injuries when is_list(injuries) ->
        tenant_injuries = Enum.filter(injuries, &(&1.organization_id == organization_id))
        exercises = if workout, do: Workouts.exercise_descriptors(workout), else: []
        evaluation = Wellbeing.evaluate_injury_risk(tenant_injuries, exercises)

        %{
          had_active_injury: tenant_injuries != [],
          injury_warning_level: Atom.to_string(evaluation.level)
        }

      _error ->
        %{}
    end
  rescue
    _error -> %{}
  end

  def completion_facts(_execution, _workout), do: %{}

  @doc """
  TD-088 abandonment facts: the completion facts plus whether the ready
  screen (`pre_start`) recorded `injury_warning_shown` /
  `injury_warning_acknowledged` for this execution. `recorded` is the set of
  `{event_name, execution_id}` pairs from `ready_screen_events/1`. Those
  events are only ever recorded from organization-provenance injuries, so
  the booleans never reveal a personal injury.
  """
  def abandonment_facts(execution, workout, %MapSet{} = recorded) do
    execution
    |> completion_facts(workout)
    |> Map.merge(%{
      injury_warning_shown: MapSet.member?(recorded, {"injury_warning_shown", execution.id}),
      injury_warning_acknowledged:
        MapSet.member?(recorded, {"injury_warning_acknowledged", execution.id})
    })
  end

  @doc """
  The ready-screen injury warning events recorded for `execution_ids` in the
  current tenant session, as a set of `{event_name, execution_id}`.
  """
  def ready_screen_events([]), do: MapSet.new()

  def ready_screen_events(execution_ids) when is_list(execution_ids) do
    ~w(injury_warning_shown injury_warning_acknowledged)
    |> Analytics.list_events_for_source_contexts(execution_ids)
    |> MapSet.new()
  end

  @doc """
  Records `event` (`injury_warning_shown` / `injury_warning_acknowledged`)
  once per actor, subject, workout, surface and UTC day. Only evaluations
  that actually warn are recorded. Always returns `:ok`.
  """
  def track(event, context, audience, workout_id, evaluation, opts \\ [])

  def track(_event, _context, _audience, _workout_id, %{level: :none}, _opts), do: :ok

  def track(event, context, audience, workout_id, evaluation, opts) do
    now = DateTime.utc_now()
    athlete_id = Keyword.get(opts, :athlete_id)
    surface = Keyword.get(opts, :surface)
    source_context_id = Keyword.get(opts, :source_context_id)

    dedupe_key =
      Enum.join(
        [
          audience,
          context.user_id,
          athlete_id || "-",
          workout_id,
          surface || "-",
          Date.to_iso8601(DateTime.to_date(now))
        ] ++ execution_scope(surface, source_context_id),
        ":"
      )

    metadata =
      evaluation
      |> Wellbeing.injury_risk_analytics_facts()
      |> Map.merge(%{
        audience: audience,
        surface: surface,
        athlete_id: athlete_id,
        scale_level_slug: Keyword.get(opts, :scale_level_slug),
        source_context_id: source_context_id
      })

    TrackAnalyticsEvent.call(event, context, nil, %{
      context_id: workout_id,
      occurred_at: now,
      dedupe_key: dedupe_key,
      metadata: metadata
    })
  end

  @doc "Keeps a surface only when it belongs to the audience's allowlist."
  def surface(value, allowed) when is_binary(value),
    do: if(value in allowed, do: value, else: nil)

  def surface(_value, _allowed), do: nil

  @doc "Keeps a slug-shaped scale level (`scaled`, `rx-plus`), otherwise `nil` (Rx)."
  def scale_slug(value) when is_binary(value) do
    if Regex.match?(~r/\A[a-z0-9][a-z0-9_-]{0,63}\z/, value), do: value, else: nil
  end

  def scale_slug(_value), do: nil

  @doc "Keeps a UUID-shaped source context id (slot, assignment) for analytics."
  def source_context_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  def source_context_id(_value), do: nil

  # The ready screen (`pre_start`) passes the execution id as its source
  # context: those events are recorded once per execution rather than once
  # per day, so an abandoned or completed execution can be joined to whether
  # its warnings were shown and acknowledged (TD-088).
  defp execution_scope("pre_start", source_context_id) when is_binary(source_context_id),
    do: [source_context_id]

  defp execution_scope(_surface, _source_context_id), do: []

  defp fetch_workout(context, workout_id) when is_binary(workout_id) do
    with {:ok, _uuid} <- cast_uuid(workout_id),
         %{} = workout <- Workouts.get_workout(context, workout_id) do
      {:ok, workout}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp fetch_workout(_context, _workout_id), do: {:error, :not_found}

  defp cast_uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> :error
    end
  end

  defp normalize_user_ids(user_ids) do
    user_ids
    |> List.wrap()
    |> Enum.filter(&match?({:ok, _uuid}, Ecto.UUID.cast(&1)))
    |> Enum.uniq()
    |> Enum.take(250)
  end
end
