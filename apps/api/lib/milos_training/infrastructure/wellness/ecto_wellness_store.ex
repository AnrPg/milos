defmodule MilosTraining.Infrastructure.Wellness.EctoWellnessStore do
  @moduledoc "Ecto adapter of the Wellness persistence port (ADR-159)."

  @behaviour MilosTraining.Wellness.Ports.WellnessStore

  import Ecto.Query

  alias MilosTraining.Repo
  alias MilosTraining.Wellness.{Craving, Entry, Preferences}

  @impl true
  def insert_entry(attrs), do: attrs |> Entry.create_changeset() |> Repo.insert()

  # A device reading is keyed by (user, source, external id). A newer reading
  # replaces the value unless the member corrected the row or deleted it.
  @impl true
  def upsert_device_entry(%{user_id: user_id, source: source, external_id: external_id} = attrs) do
    case Repo.get_by(Entry, user_id: user_id, source: source, external_id: external_id) do
      nil ->
        insert_entry(attrs)

      %Entry{deleted_at: nil, corrected_at: nil} = entry ->
        entry |> Entry.device_changeset(attrs) |> Repo.update()

      %Entry{} = kept ->
        {:ok, kept}
    end
  end

  @impl true
  def get_entry(id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Entry
      |> where([e], e.id == ^id and e.user_id == ^user_id and is_nil(e.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  @impl true
  def change_entry(%Entry{} = entry, attrs, now),
    do: entry |> Entry.change_changeset(attrs, now) |> Repo.update()

  @impl true
  def set_entry_visibility(%Entry{} = entry, rung),
    do: entry |> Entry.visibility_changeset(rung) |> Repo.update()

  @impl true
  def delete_entry(%Entry{} = entry, now),
    do: entry |> Entry.delete_changeset(now) |> Repo.update()

  @impl true
  def list_entries(user_id, %Date{} = from, %Date{} = to) do
    Entry
    |> where([e], e.user_id == ^user_id and is_nil(e.deleted_at))
    |> where([e], e.occurred_on >= ^from and e.occurred_on <= ^to)
    |> order_by([e], asc: e.occurred_at, asc: e.id)
    |> Repo.all()
  end

  @impl true
  def insert_craving(attrs), do: attrs |> Craving.create_changeset() |> Repo.insert()

  @impl true
  def get_craving(id, user_id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Craving
      |> where([c], c.id == ^id and c.user_id == ^user_id and is_nil(c.deleted_at))
      |> Repo.one()
    else
      :error -> nil
    end
  end

  @impl true
  def change_craving(%Craving{} = craving, attrs),
    do: craving |> Craving.change_changeset(attrs) |> Repo.update()

  @impl true
  def set_craving_visibility(%Craving{} = craving, rung),
    do: craving |> Craving.visibility_changeset(rung) |> Repo.update()

  @impl true
  def delete_craving(%Craving{} = craving, now),
    do: craving |> Craving.delete_changeset(now) |> Repo.update()

  @impl true
  def list_cravings(user_id, %Date{} = from, %Date{} = to) do
    Craving
    |> where([c], c.user_id == ^user_id and is_nil(c.deleted_at))
    |> where([c], c.occurred_on >= ^from and c.occurred_on <= ^to)
    |> order_by([c], asc: c.occurred_at, asc: c.id)
    |> Repo.all()
  end

  # Runs in the platform session of the follow-up job.
  @impl true
  # Platform sweeps: definer lookups that answer ids only; each person is
  # then handled in their own session.
  def craving_follow_ups_due(%DateTime{} = now, limit) do
    %{rows: rows} =
      Repo.query!("SELECT user_id, craving_id FROM milos_craving_follow_ups_due($1, $2)", [
        DateTime.to_naive(now),
        limit
      ])

    Enum.map(rows, fn [user_id, id] -> {Ecto.UUID.load!(user_id), Ecto.UUID.load!(id)} end)
  end

  @impl true
  def mark_followed_up(%Craving{} = craving, at),
    do: craving |> Craving.followed_up_changeset(at) |> Repo.update()

  @impl true
  def get_preferences(user_id), do: Repo.get_by(Preferences, user_id: user_id)

  @impl true
  def water_reminders_due(%DateTime{} = now, limit) do
    %{rows: rows} =
      Repo.query!("SELECT user_id, local_day FROM milos_water_reminders_due($1, $2)", [
        DateTime.to_naive(now),
        limit
      ])

    Enum.map(rows, fn [user_id, day] -> {Ecto.UUID.load!(user_id), day} end)
  end

  @impl true
  def mark_water_reminded(user_id, %Date{} = day) do
    Preferences
    |> where([p], p.user_id == ^user_id)
    |> Repo.update_all(set: [water_reminded_on: day, updated_at: DateTime.utc_now()])

    :ok
  end

  @impl true
  def put_preferences(user_id, attrs) do
    (get_preferences(user_id) || %Preferences{user_id: user_id})
    |> Preferences.changeset(Map.put(attrs, :user_id, user_id))
    |> Repo.insert_or_update()
  end

  # «Διαγραφή όλων»: soft-deleted rows are gone for the member at once; the
  # rows themselves go, too, since nothing else references them.
  @impl true
  def erase(user_id, sections, _now) do
    Map.new(sections, fn
      "wellness" ->
        {count, _rows} = Entry |> where([e], e.user_id == ^user_id) |> Repo.delete_all()
        Preferences |> where([p], p.user_id == ^user_id) |> Repo.delete_all()
        {"wellness", count}

      "cravings" ->
        {count, _rows} = Craving |> where([c], c.user_id == ^user_id) |> Repo.delete_all()
        {"cravings", count}
    end)
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
