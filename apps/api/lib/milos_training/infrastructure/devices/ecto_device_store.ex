defmodule MilosTraining.Infrastructure.Devices.EctoDeviceStore do
  @moduledoc "Ecto adapter of the Devices persistence port (ADR-161)."

  @behaviour MilosTraining.Devices.Ports.DeviceStore

  import Ecto.Query

  alias MilosTraining.Devices.{Connection, DailyStat, DeviceActivity, DeviceImport}
  alias MilosTraining.Infrastructure.Journal.{FeedBound, FeedScope}
  alias MilosTraining.Repo

  # Connections ---------------------------------------------------------------

  @impl true
  def get_connection(user_id, provider),
    do: Repo.get_by(Connection, user_id: user_id, provider: provider)

  @impl true
  def insert_connection(attrs), do: attrs |> Connection.changeset() |> Repo.insert()

  @impl true
  def update_connection(%Connection{} = connection, attrs),
    do: connection |> Connection.changeset(attrs) |> Repo.update()

  @impl true
  def list_connections(user_id) do
    Connection
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], asc: c.provider)
    |> Repo.all()
  end

  @impl true
  def oauth_state_lookup(state_hash) do
    case Repo.query!("SELECT id, user_id FROM milos_device_connection_by_oauth_state($1)", [
           state_hash
         ]) do
      %{rows: [[id, user_id] | _rest]} -> {Ecto.UUID.load!(id), Ecto.UUID.load!(user_id)}
      %{rows: []} -> nil
    end
  end

  @impl true
  def provider_users_lookup(_provider, []), do: []

  def provider_users_lookup(provider, ids) do
    %{rows: rows} =
      Repo.query!(
        "SELECT id, user_id, provider_user_id, status FROM milos_device_connections_for_provider_users($1, $2)",
        [provider, ids]
      )

    Enum.map(rows, fn [id, user_id, provider_user_id, status] ->
      %{
        id: Ecto.UUID.load!(id),
        user_id: Ecto.UUID.load!(user_id),
        provider_user_id: provider_user_id,
        status: status
      }
    end)
  end

  @impl true
  def refresh_due_lookup(before, limit) do
    %{rows: rows} =
      Repo.query!("SELECT id, user_id FROM milos_device_connections_due_refresh($1, $2)", [
        DateTime.to_naive(before),
        limit
      ])

    Enum.map(rows, fn [id, user_id] -> {Ecto.UUID.load!(id), Ecto.UUID.load!(user_id)} end)
  end

  # Imports -------------------------------------------------------------------

  @impl true
  def get_import(user_id, provider, kind, provider_id),
    do:
      Repo.get_by(DeviceImport,
        user_id: user_id,
        provider: provider,
        kind: kind,
        provider_id: provider_id
      )

  @impl true
  def get_import_by_id(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(DeviceImport, id: id, user_id: user_id)
      :error -> nil
    end
  end

  @impl true
  # A summary Garmin sends twice (a retried push) must not abort the
  # surrounding transaction, so the conflict is skipped, then detected.
  def insert_import(attrs) do
    with {:ok, import} <-
           attrs
           |> DeviceImport.changeset()
           |> Repo.insert(
             on_conflict: :nothing,
             conflict_target: [:user_id, :provider, :kind, :provider_id]
           ) do
      case get_import(import.user_id, import.provider, import.kind, import.provider_id) do
        %DeviceImport{id: id} = stored when id == import.id -> {:ok, stored}
        _other -> {:error, :duplicate_import}
      end
    end
  end

  @impl true
  def update_import(%DeviceImport{} = import, attrs),
    do: import |> DeviceImport.changeset(attrs) |> Repo.update()

  @impl true
  def list_imports_since(user_id, since) do
    DeviceImport
    |> where([i], i.user_id == ^user_id)
    |> then(fn query ->
      if since, do: where(query, [i], i.received_at > ^since), else: query
    end)
    |> order_by([i], desc: i.received_at)
    |> limit(500)
    |> Repo.all()
  end

  @impl true
  def list_imports(user_id, provider) do
    DeviceImport
    |> where([i], i.user_id == ^user_id and i.provider == ^provider)
    |> Repo.all()
  end

  @impl true
  def delete_imports(user_id, provider) do
    {count, _rows} =
      DeviceImport
      |> where([i], i.user_id == ^user_id and i.provider == ^provider)
      |> Repo.delete_all()

    count
  end

  # Activities ----------------------------------------------------------------

  @impl true
  def insert_activity(attrs), do: attrs |> DeviceActivity.changeset() |> Repo.insert()

  @impl true
  def update_activity(%DeviceActivity{} = activity, attrs),
    do: activity |> DeviceActivity.changeset(attrs) |> Repo.update()

  @impl true
  def get_activity(id, user_id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(DeviceActivity, id: id, user_id: user_id)
      :error -> nil
    end
  end

  @impl true
  def list_pending_activities(user_id) do
    DeviceActivity
    |> where([a], a.user_id == ^user_id and a.state == "pending")
    |> order_by([a], desc: a.started_at)
    |> Repo.all()
  end

  @impl true
  def list_activity_items(user_id, bound, limit, scope) do
    DeviceActivity
    |> where([a], a.state == "own")
    |> FeedScope.apply(user_id, scope,
      kind: "device_activity",
      at: :started_at,
      text: [:title],
      device: :provider
    )
    |> FeedBound.apply(:started_at, bound)
    |> order_by([a], desc: a.started_at, desc: a.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def list_merged(_kind, []), do: []

  def list_merged(kind, ids) do
    DeviceActivity
    |> where([a], a.state == "merged" and a.merged_kind == ^kind and a.merged_id in ^ids)
    |> Repo.all()
  end

  @impl true
  def match_candidates(from, to) do
    %{rows: rows} =
      Repo.query!(
        "SELECT kind, id, organization_id, title, starts_at, ends_at FROM milos_device_match_candidates($1, $2)",
        [DateTime.to_naive(from), DateTime.to_naive(to)]
      )

    Enum.map(rows, fn [kind, id, organization_id, title, starts_at, ends_at] ->
      %{
        kind: kind,
        id: Ecto.UUID.load!(id),
        organization_id: organization_id && Ecto.UUID.load!(organization_id),
        title: title,
        starts_at: DateTime.from_naive!(starts_at, "Etc/UTC"),
        ends_at: DateTime.from_naive!(ends_at, "Etc/UTC")
      }
    end)
  end

  @impl true
  def list_activities_between(user_id, from, to) do
    DeviceActivity
    |> where([a], a.user_id == ^user_id and a.started_at >= ^from and a.started_at <= ^to)
    |> order_by([a], asc: a.started_at)
    |> Repo.all()
  end

  @impl true
  def list_activities(user_id) do
    DeviceActivity
    |> where([a], a.user_id == ^user_id)
    |> order_by([a], asc: a.started_at, asc: a.id)
    |> Repo.all()
  end

  @impl true
  def delete_activities(user_id, provider) do
    {count, _rows} =
      DeviceActivity
      |> where([a], a.user_id == ^user_id and a.provider == ^provider)
      |> Repo.delete_all()

    count
  end

  # Daily stats ---------------------------------------------------------------

  @impl true
  def upsert_daily_stat(attrs) do
    # Only the numbers this import carries are replaced: a day's steps and
    # its resting heart rate arrive separately into the same row.
    replaced = Enum.filter([:resting_heart_rate, :steps], &Map.has_key?(attrs, &1))

    attrs
    |> DailyStat.changeset()
    |> Repo.insert(
      on_conflict: {:replace, replaced ++ [:updated_at]},
      conflict_target: [:user_id, :on, :source],
      returning: true
    )
  end

  @impl true
  def list_daily_stats(user_id, %Date{} = from, %Date{} = to) do
    DailyStat
    |> where([s], s.user_id == ^user_id and s.on >= ^from and s.on <= ^to)
    |> order_by([s], asc: s.on)
    |> Repo.all()
  end

  @impl true
  def list_all_daily_stats(user_id) do
    DailyStat
    |> where([s], s.user_id == ^user_id)
    |> order_by([s], asc: s.on, asc: s.source)
    |> Repo.all()
  end

  @impl true
  def delete_daily_stats(user_id, source) do
    {count, _rows} =
      DailyStat
      |> where([s], s.user_id == ^user_id and s.source == ^source)
      |> Repo.delete_all()

    count
  end

  @impl true
  def transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        {:ok, value} -> value
        value -> value
      end
    end)
  end
end
