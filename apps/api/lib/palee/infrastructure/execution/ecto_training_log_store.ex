defmodule Palee.Infrastructure.Execution.EctoTrainingLogStore do
  @moduledoc """
  Ecto adapter for standalone training-log entries (ADR-118).

  Ownership is always taken from the session GUCs opened by `RepoContext`,
  never from caller params: inserts stamp `organization_id` / `user_id` from
  `app.organization_id` / `app.user_id`, and reads are restricted to the
  acting user's rows (within the tenant when one is open).
  """

  @behaviour Palee.Execution.Ports.TrainingLogStore

  import Ecto.Query

  alias Ecto.Multi
  alias Palee.Execution.TrainingLogEntry
  alias Palee.Infrastructure.Journal.{FeedBound, FeedScope}
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Repo

  @impl true
  def create_entry(params, job_builder) do
    with {:ok, organization_id, user_id} <- tenant_owner() do
      params =
        params
        |> Map.put(:organization_id, organization_id)
        |> Map.put(:user_id, user_id)

      changeset = TrainingLogEntry.create_changeset(%TrainingLogEntry{}, params)

      Multi.new()
      |> Multi.insert(:entry, changeset)
      |> maybe_enqueue(job_builder)
      |> Repo.transaction()
      |> case do
        {:ok, %{entry: entry}} ->
          {:ok, normalize(entry)}

        {:error, :entry, %Ecto.Changeset{} = changeset, _changes} ->
          translate_insert_error(changeset, user_id, params)

        {:error, :completion_job, _reason, _changes} ->
          {:error, :completion_processing_unavailable}
      end
    end
  end

  @impl true
  def get_entry_by_idempotency_key(user_id, key) do
    TrainingLogEntry
    |> scoped()
    |> where([entry], entry.user_id == ^user_id and entry.idempotency_key == ^key)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def update_entry(id, params, expected_version) do
    mutate(id, expected_version, &TrainingLogEntry.update_changeset(&1, params))
  end

  @impl true
  def void_entry(id, params, expected_version) do
    mutate(id, expected_version, &TrainingLogEntry.void_changeset(&1, params))
  end

  @impl true
  def get_entry(id) do
    TrainingLogEntry
    |> scoped()
    |> where([entry], entry.id == ^id)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def list_entries_for_user(user_id, opts) do
    TrainingLogEntry
    |> scoped(Keyword.get(opts, :across_tenants, false))
    |> where([entry], entry.user_id == ^user_id)
    |> maybe_only_logged(Keyword.get(opts, :include_voided, true))
    |> order_by([entry], desc: entry.performed_at_utc, desc: entry.inserted_at)
    |> maybe_limit(Keyword.get(opts, :limit))
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def list_live_source_reference_ids(user_id, source_type) do
    TrainingLogEntry
    |> scoped()
    |> where(
      [entry],
      entry.user_id == ^user_id and entry.source_type == ^source_type and
        entry.status == "logged" and not is_nil(entry.source_reference_id)
    )
    |> select([entry], entry.source_reference_id)
    |> Repo.all()
  end

  defp mutate(id, expected_version, build_changeset) do
    Repo.transaction(fn ->
      case TrainingLogEntry
           |> scoped()
           |> where([entry], entry.id == ^id)
           |> lock("FOR UPDATE")
           |> Repo.one() do
        nil ->
          Repo.rollback(:not_found)

        %TrainingLogEntry{status: "voided"} ->
          Repo.rollback(:training_log_entry_voided)

        %TrainingLogEntry{lock_version: version}
        when is_integer(expected_version) and expected_version != version ->
          Repo.rollback(:stale_training_log_entry)

        %TrainingLogEntry{} = entry ->
          entry
          |> build_changeset.()
          |> Repo.update(stale_error_field: :lock_version)
          |> case do
            {:ok, updated} -> normalize(updated)
            {:error, %{errors: [lock_version: _]}} -> Repo.rollback(:stale_training_log_entry)
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  defp maybe_enqueue(multi, nil), do: multi

  defp maybe_enqueue(multi, job_builder) when is_function(job_builder, 1),
    do: Oban.insert(multi, :completion_job, fn %{entry: entry} -> job_builder.(entry) end)

  defp translate_insert_error(changeset, user_id, params) do
    cond do
      constraint_error?(changeset, :idempotency_key) ->
        # A concurrent duplicate submission won the race; return its result.
        case get_entry_by_idempotency_key(user_id, params[:idempotency_key]) do
          nil -> {:error, changeset}
          entry -> {:ok, entry}
        end

      constraint_error?(changeset, :source_reference_id) and
          Keyword.has_key?(changeset.errors, :source_reference_id) ->
        {:error, :training_log_source_already_logged}

      true ->
        {:error, changeset}
    end
  end

  defp constraint_error?(changeset, field) do
    Enum.any?(changeset.errors, fn
      {^field, {_message, opts}} -> Keyword.get(opts, :constraint) == :unique
      _other -> false
    end)
  end

  defp maybe_only_logged(query, true), do: query
  defp maybe_only_logged(query, false), do: where(query, [entry], entry.status == "logged")

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _limit), do: query

  defp tenant_owner do
    organization_id = RepoContext.current_setting("app.organization_id")
    user_id = RepoContext.current_setting("app.user_id")

    if is_binary(organization_id) and is_binary(user_id),
      do: {:ok, organization_id, user_id},
      else: {:error, :organization_context_required}
  end

  # Owner rows only. Within a tenant session the organization is pinned too,
  # unless the caller explicitly asks for the owner's rows across tenants
  # (personal gamification projection); RLS still requires the owner match.
  # Journal feed (ADR-139 §9): logged (not voided) entries, newest first,
  # after the page bound, for the owner across gyms or for a coach of one gym.
  @impl true
  def list_entry_items(user_id, bound, limit, scope) do
    TrainingLogEntry
    |> where([entry], entry.status == "logged")
    |> FeedScope.apply(user_id, scope,
      kind: "training_log",
      at: :performed_at_utc,
      text: [:title],
      text_exists: :comments,
      device: :source_type
    )
    |> FeedBound.apply(:performed_at_utc, bound)
    |> order_by([entry], desc: entry.performed_at_utc, desc: entry.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def list_for_workout(organization_id, workout_id, from, to) do
    TrainingLogEntry
    |> where(
      [entry],
      entry.organization_id == ^organization_id and entry.master_workout_id == ^workout_id and
        entry.status != "voided" and entry.performed_at_utc >= ^from and
        entry.performed_at_utc < ^to
    )
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def set_entry_visibility(id, user_id, rung) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %TrainingLogEntry{} = entry <- Repo.get_by(TrainingLogEntry, id: id, user_id: user_id) do
      entry
      |> TrainingLogEntry.visibility_changeset(rung)
      |> Repo.update()
      |> case do
        {:ok, updated} -> {:ok, normalize(updated)}
        error -> error
      end
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def move_entries(user_id, from, to) do
    {count, _rows} =
      TrainingLogEntry
      |> where([entry], entry.user_id == ^user_id and entry.journal_visibility in ^from)
      |> Repo.update_all(set: [journal_visibility: to, updated_at: DateTime.utc_now()])

    count
  end

  defp scoped(query, across_tenants? \\ false) do
    organization_id = RepoContext.current_setting("app.organization_id")
    user_id = RepoContext.current_setting("app.user_id")

    cond do
      is_binary(organization_id) and is_binary(user_id) and not across_tenants? ->
        where(
          query,
          [entry],
          entry.organization_id == ^organization_id and entry.user_id == ^user_id
        )

      is_binary(user_id) ->
        where(query, [entry], entry.user_id == ^user_id)

      true ->
        where(query, [entry], false)
    end
  end

  defp normalize(nil), do: nil

  defp normalize(%TrainingLogEntry{} = entry) do
    %{
      id: entry.id,
      organization_id: entry.organization_id,
      user_id: entry.user_id,
      source_type: entry.source_type,
      source_reference_id: entry.source_reference_id,
      master_workout_id: entry.master_workout_id,
      booking_id: entry.booking_id,
      title: entry.title,
      workout_type: entry.workout_type,
      scale_level_slug: entry.scale_level_slug,
      performed_at_utc: entry.performed_at_utc,
      performed_at_tz: entry.performed_at_tz,
      duration_seconds: entry.duration_seconds,
      perceived_effort: entry.perceived_effort,
      section_scores: entry.section_scores || [],
      performed_exercises: entry.performed_exercises || [],
      status: entry.status,
      voided_at: entry.voided_at,
      void_reason: entry.void_reason,
      idempotency_key: entry.idempotency_key,
      lock_version: entry.lock_version,
      journal_visibility: entry.journal_visibility,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end
end
