defmodule MilosTraining.Application.InjuryWarningEvaluation do
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

  alias MilosTraining.Application.TrackAnalyticsEvent
  alias MilosTraining.{Wellbeing, Workouts}

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
      with {:ok, workout} <- fetch_workout(workout_id) do
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
  """
  def for_self(%{organization_id: organization_id, user_id: user_id} = context, workout_id)
      when is_binary(organization_id) and is_binary(user_id) do
    context
    |> Wellbeing.with_tenant_context(fn ->
      with {:ok, workout} <- fetch_workout(workout_id) do
        {:ok, workout, Wellbeing.list_active_injuries_for_user(user_id)}
      end
    end)
    |> case do
      {:ok, workout, injuries} ->
        exercises = Workouts.exercise_descriptors(workout)
        evaluation = Wellbeing.evaluate_injury_risk(injuries, exercises)

        tenant_evaluation =
          injuries
          |> Enum.filter(&(&1.organization_id == organization_id))
          |> Wellbeing.evaluate_injury_risk(exercises)

        {:ok, %{workout_id: workout.id, level: evaluation.level, warnings: evaluation.warnings},
         tenant_evaluation}

      {:error, _reason} = error ->
        error
    end
  end

  def for_self(_context, _workout_id), do: {:error, :organization_context_required}

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

    dedupe_key =
      Enum.join(
        [
          audience,
          context.user_id,
          athlete_id || "-",
          workout_id,
          surface || "-",
          Date.to_iso8601(DateTime.to_date(now))
        ],
        ":"
      )

    metadata =
      evaluation
      |> Wellbeing.injury_risk_analytics_facts()
      |> Map.merge(%{
        audience: audience,
        surface: surface,
        athlete_id: athlete_id,
        source_context_id: Keyword.get(opts, :source_context_id)
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

  @doc "Keeps a UUID-shaped source context id (slot, assignment) for analytics."
  def source_context_id(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  def source_context_id(_value), do: nil

  defp fetch_workout(workout_id) when is_binary(workout_id) do
    with {:ok, _uuid} <- cast_uuid(workout_id),
         %{} = workout <- Workouts.get_workout(workout_id) do
      {:ok, workout}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp fetch_workout(_workout_id), do: {:error, :not_found}

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
