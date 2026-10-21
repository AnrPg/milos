defmodule Palee.Infrastructure.Body.EctoBodyStore do
  @moduledoc """
  Ecto adapter of the Body store (ADR-158). Queries name the owner
  explicitly; row security (owner policies, the coach read policies) is the
  second wall.
  """

  @behaviour Palee.Body.Ports.BodyStore

  import Ecto.Query

  alias Palee.Body.{AccessLogEntry, HealthConsent, Settings, Snapshot, SnapshotPhoto}
  alias Palee.Repo

  @shared ~w(coach_numbers coach_full)

  @impl true
  def list_snapshots(_context, user_id, opts) do
    Snapshot
    |> where([s], s.user_id == ^user_id)
    |> shared_only(Keyword.get(opts, :shared_only, false))
    |> after_cursor(Keyword.get(opts, :cursor))
    |> private_only(Keyword.get(opts, :private_only, false))
    |> taken_since(Keyword.get(opts, :since))
    |> taken_before(Keyword.get(opts, :before))
    |> feed_bound(Keyword.get(opts, :bound, :none))
    |> order_by([s], desc: s.taken_at, desc: s.id)
    |> limit(^Keyword.get(opts, :limit, 21))
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  defp shared_only(query, false), do: query
  defp shared_only(query, true), do: where(query, [s], s.visibility in @shared)

  defp private_only(query, false), do: query
  defp private_only(query, true), do: where(query, [s], s.visibility not in @shared)

  defp after_cursor(query, nil), do: query

  defp after_cursor(query, %{taken_at: at, id: id}) do
    where(
      query,
      [s],
      s.taken_at < ^at or (s.taken_at == ^at and s.id < type(^id, :binary_id))
    )
  end

  defp taken_since(query, nil), do: query
  defp taken_since(query, %DateTime{} = at), do: where(query, [s], s.taken_at >= ^at)

  defp taken_before(query, nil), do: query
  defp taken_before(query, %DateTime{} = at), do: where(query, [s], s.taken_at < ^at)

  # A journal feed bound (`Journal.feed_bound/2`).
  defp feed_bound(query, :none), do: query
  defp feed_bound(query, {:before, at}), do: where(query, [s], s.taken_at < ^at)
  defp feed_bound(query, {:at_most, at}), do: where(query, [s], s.taken_at <= ^at)
  defp feed_bound(query, {:before_id, at, id}), do: after_cursor(query, %{taken_at: at, id: id})

  @impl true
  def get_snapshot(_context, user_id, id, opts) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Snapshot{} = snapshot <-
           Snapshot
           |> where([s], s.id == ^id and s.user_id == ^user_id)
           |> shared_only(Keyword.get(opts, :shared_only, false))
           |> Repo.one() do
      normalize(snapshot)
    else
      _missing -> nil
    end
  end

  @impl true
  def create_snapshot(_context, attrs) do
    attrs
    |> Snapshot.changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def update_snapshot(_context, user_id, id, attrs) do
    case own_snapshot(user_id, id) do
      nil -> {:error, :not_found}
      snapshot -> snapshot |> Snapshot.changeset(attrs) |> Repo.update() |> normalize_result()
    end
  end

  @impl true
  def delete_snapshot(_context, user_id, id) do
    case own_snapshot(user_id, id) do
      nil -> {:error, :not_found}
      snapshot -> snapshot |> Repo.delete() |> normalize_result()
    end
  end

  @impl true
  def delete_empty_snapshots(_context, user_id) do
    {count, _rows} =
      from(s in Snapshot,
        as: :snapshot,
        where: s.user_id == ^user_id and s.metrics == ^%{},
        where:
          not exists(from(p in SnapshotPhoto, where: p.snapshot_id == parent_as(:snapshot).id))
      )
      |> Repo.delete_all()

    count
  end

  @impl true
  def list_metric_points(_context, user_id, key, since, opts) do
    Snapshot
    |> where([s], s.user_id == ^user_id)
    |> shared_only(Keyword.get(opts, :shared_only, false))
    |> where([s], fragment("jsonb_typeof(? -> ?) = 'number'", s.metrics, ^key))
    |> then(fn query ->
      if since, do: where(query, [s], s.taken_at >= ^since), else: query
    end)
    |> order_by([s], asc: s.taken_at, asc: s.id)
    |> select([s], %{
      at: s.taken_at,
      value: fragment("(? ->> ?)::float8", s.metrics, ^key),
      snapshot_id: s.id
    })
    |> Repo.all()
  end

  @impl true
  def latest_taken_at(_context, user_id) do
    Snapshot
    |> where([s], s.user_id == ^user_id)
    |> select([s], max(s.taken_at))
    |> Repo.one()
  end

  @impl true
  def list_photos(_context, []), do: []

  def list_photos(_context, snapshot_ids) do
    SnapshotPhoto
    |> where([p], p.snapshot_id in ^snapshot_ids)
    |> order_by([p], asc: p.inserted_at, asc: p.id)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def insert_photo(_context, attrs) do
    attrs
    |> SnapshotPhoto.changeset()
    |> Repo.insert()
    |> normalize_result()
  end

  @impl true
  def get_photo(_context, user_id, photo_id) do
    case Ecto.UUID.cast(photo_id) do
      {:ok, id} ->
        SnapshotPhoto
        |> where([p], p.id == ^id and p.user_id == ^user_id)
        |> Repo.one()
        |> normalize()

      :error ->
        nil
    end
  end

  @impl true
  def delete_photo(_context, user_id, photo_id) do
    with {:ok, id} <- Ecto.UUID.cast(photo_id),
         %SnapshotPhoto{} = photo <-
           SnapshotPhoto |> where([p], p.id == ^id and p.user_id == ^user_id) |> Repo.one() do
      photo |> Repo.delete() |> normalize_result()
    else
      _missing -> {:error, :not_found}
    end
  end

  @impl true
  def refresh_photo(%{user_id: user_id}, media_id, attrs) do
    changes =
      attrs
      |> Map.take([:status, :variants, :width, :height, :placeholder])
      |> Map.put(:updated_at, DateTime.utc_now())
      |> Map.to_list()

    SnapshotPhoto
    |> where([p], p.media_id == ^media_id and p.user_id == ^user_id)
    |> Repo.update_all(set: changes)

    :ok
  end

  @impl true
  def latest_photos(_context, user_id) do
    SnapshotPhoto
    |> join(:inner, [p], s in Snapshot, on: s.id == p.snapshot_id)
    |> where([p], p.user_id == ^user_id and p.status == "ready")
    |> distinct([p], p.pose)
    |> order_by([p, s], asc: p.pose, desc: s.taken_at, desc: p.inserted_at)
    |> select([p, s], {p, s.taken_at})
    |> Repo.all()
    |> Enum.map(fn {photo, taken_at} -> photo |> normalize() |> Map.put(:taken_at, taken_at) end)
  end

  @impl true
  def get_settings(_context, user_id) do
    Settings
    |> where([s], s.user_id == ^user_id)
    |> Repo.one()
    |> normalize()
  end

  @impl true
  def put_settings(_context, _user_id, changes) when map_size(changes) == 0, do: {:ok, nil}

  def put_settings(_context, user_id, changes) do
    fields = Map.keys(changes)

    %Settings{user_id: user_id}
    |> Ecto.Changeset.change(Map.merge(defaults_for_insert(), changes))
    |> Repo.insert(
      on_conflict: {:replace, [:updated_at | fields]},
      conflict_target: [:user_id],
      returning: true
    )
    |> normalize_result()
  end

  defp defaults_for_insert,
    do: %{journal_sections: %{"body" => true, "wellness" => true, "cravings" => true}}

  @impl true
  def list_consents(_context, user_id) do
    HealthConsent
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.granted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def grant_consent(_context, user_id, scope, now) do
    active =
      HealthConsent
      |> where([c], c.user_id == ^user_id and c.scope == ^scope and is_nil(c.withdrawn_at))
      |> Repo.one()

    case active do
      %HealthConsent{} = consent ->
        {:ok, normalize(consent)}

      nil ->
        {:ok, _consent} =
          Repo.insert(%HealthConsent{user_id: user_id, scope: scope, granted_at: now},
            on_conflict: :nothing,
            conflict_target: {:unsafe_fragment, "(user_id, scope) WHERE withdrawn_at IS NULL"}
          )

        # A concurrent grant may have won; either way one grant is active.
        HealthConsent
        |> where([c], c.user_id == ^user_id and c.scope == ^scope and is_nil(c.withdrawn_at))
        |> Repo.one()
        |> then(&{:ok, normalize(&1)})
    end
  end

  @impl true
  def withdraw_consent(_context, user_id, scope, now) do
    {count, _rows} =
      HealthConsent
      |> where([c], c.user_id == ^user_id and c.scope == ^scope and is_nil(c.withdrawn_at))
      |> Repo.update_all(set: [withdrawn_at: now, updated_at: now])

    count
  end

  @impl true
  def photos_consented?(_context, user_id) do
    %{rows: [[consented]]} =
      Repo.query!("SELECT palee_body_photos_consented($1)", [Ecto.UUID.dump!(user_id)])

    consented == true
  end

  @impl true
  def record_access(_context, attrs) do
    now = DateTime.utc_now()

    entry =
      attrs
      |> Map.take([
        :organization_id,
        :user_id,
        :reader_user_id,
        :subject,
        :snapshot_ids,
        :photos_shown
      ])
      |> Map.merge(%{id: Ecto.UUID.generate(), read_at: now, inserted_at: now})

    {1, _rows} = Repo.insert_all(AccessLogEntry, [entry])
    :ok
  end

  @impl true
  def list_access_log(_context, user_id, limit) do
    AccessLogEntry
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], desc: a.read_at, desc: a.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def reminders_due(now, limit) do
    %{rows: rows} =
      Repo.query!("SELECT id FROM palee_body_reminders_due($1, $2) AS id", [
        DateTime.to_naive(now),
        limit
      ])

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  @impl true
  def mark_reminded(_context, user_id, now) do
    Settings
    |> where([s], s.user_id == ^user_id)
    |> Repo.update_all(set: [last_reminded_at: now, updated_at: now])

    :ok
  end

  defp own_snapshot(user_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Snapshot |> where([s], s.id == ^id and s.user_id == ^user_id) |> Repo.one()
      :error -> nil
    end
  end

  defp normalize_result({:ok, row}), do: {:ok, normalize(row)}
  defp normalize_result({:error, changeset}), do: {:error, changeset}

  defp normalize(nil), do: nil

  defp normalize(%_{} = row),
    do: row |> Map.from_struct() |> Map.drop([:__meta__])
end
