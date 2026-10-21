defmodule Palee.Infrastructure.Community.EctoEventStore do
  @moduledoc "Ecto adapter for club events and their attendees (ADR-153)."

  @behaviour Palee.Community.Ports.EventStore

  import Ecto.Query

  alias Palee.Community.{Event, EventAttendee}
  alias Palee.Repo

  # Events ---------------------------------------------------------------------

  @impl true
  def insert_events(_context, attrs_list) do
    Repo.transaction(fn ->
      Enum.map(attrs_list, fn attrs ->
        case attrs |> Event.create_changeset() |> Repo.insert() do
          {:ok, event} -> event
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @impl true
  def get_event(_context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Event, id)
      :error -> nil
    end
  end

  @impl true
  def list_events(_context, filter) do
    Event
    |> filter_organizations(filter[:organization_ids])
    |> filter_ids(filter[:ids])
    |> filter_cover(filter[:cover_media_id])
    |> filter_clubs(filter[:club_ids])
    |> filter_series(filter[:series_id])
    |> filter_from(filter[:from])
    |> filter_to(filter[:to])
    |> filter_ended_before(filter[:ended_before])
    |> filter_open(filter[:open_only])
    |> filter_good_for_friends(filter[:good_for_friends])
    |> filter_cancelled(filter[:include_cancelled])
    |> order_events(filter[:order] || :asc)
    |> limit(^min(filter[:limit] || 200, 500))
    |> Repo.all()
  end

  defp filter_organizations(query, nil), do: query
  defp filter_organizations(query, ids), do: where(query, [e], e.organization_id in ^ids)
  defp filter_cover(query, nil), do: query
  defp filter_cover(query, id), do: where(query, [e], e.cover_media_id == ^id)
  defp filter_ids(query, nil), do: query
  defp filter_ids(query, ids), do: where(query, [e], e.id in ^ids)
  defp filter_clubs(query, nil), do: query
  defp filter_clubs(query, ids), do: where(query, [e], e.club_id in ^ids)
  defp filter_series(query, nil), do: query
  defp filter_series(query, id), do: where(query, [e], e.series_id == ^id)
  defp filter_from(query, nil), do: query
  defp filter_from(query, at), do: where(query, [e], e.ends_at > ^at)
  defp filter_to(query, nil), do: query
  defp filter_to(query, at), do: where(query, [e], e.starts_at < ^at)
  defp filter_ended_before(query, nil), do: query
  defp filter_ended_before(query, at), do: where(query, [e], e.ends_at <= ^at)
  defp filter_open(query, true), do: where(query, [e], e.open_to_non_members)
  defp filter_open(query, _all), do: query
  defp filter_good_for_friends(query, true), do: where(query, [e], e.good_for_friends)
  defp filter_good_for_friends(query, _all), do: query
  defp filter_cancelled(query, true), do: query
  defp filter_cancelled(query, _live), do: where(query, [e], is_nil(e.cancelled_at))

  defp order_events(query, :asc), do: order_by(query, [e], asc: e.starts_at, asc: e.id)
  defp order_events(query, :desc), do: order_by(query, [e], desc: e.starts_at, desc: e.id)

  @impl true
  def update_event(_context, event, attrs),
    do: event |> Event.update_changeset(attrs) |> Repo.update()

  @impl true
  def set_event_lifecycle(_context, event, attrs),
    do: event |> Event.lifecycle_changeset(attrs) |> Repo.update()

  @impl true
  def claim_event(_context, id, field, now)
      when field in [:reminder_sent_at, :trial_offer_sent_at] do
    Event
    |> where([e], e.id == ^id and is_nil(field(e, ^field)))
    |> select([e], e)
    |> Repo.update_all(set: [{field, now}, {:updated_at, now}])
    |> case do
      {1, [event]} -> {:ok, event}
      _taken -> {:error, :already_claimed}
    end
  end

  @impl true
  def reminders_due(%{organization_id: organization_id}, %{from: from, to: to}) do
    Event
    |> where(
      [e],
      e.organization_id == ^organization_id and is_nil(e.reminder_sent_at) and
        is_nil(e.cancelled_at) and e.starts_at > ^from and e.starts_at <= ^to
    )
    |> Repo.all()
  end

  @impl true
  def with_event_lock(_context, id, fun) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        case Repo.one(from e in Event, where: e.id == ^id, lock: "FOR UPDATE") do
          nil ->
            Repo.rollback(:not_found)

          event ->
            case fun.(event) do
              {:error, reason} -> Repo.rollback(reason)
              result -> result
            end
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  # Attendees ------------------------------------------------------------------

  @impl true
  def get_attendee(_context, event_id, user_id) do
    with {:ok, event_id} <- Ecto.UUID.cast(event_id),
         {:ok, user_id} <- Ecto.UUID.cast(user_id) do
      Repo.get_by(EventAttendee, event_id: event_id, user_id: user_id)
    else
      :error -> nil
    end
  end

  @impl true
  def list_attendees(_context, [], _statuses), do: []

  def list_attendees(_context, event_ids, statuses) do
    EventAttendee
    |> where([a], a.event_id in ^event_ids)
    |> then(fn query ->
      if statuses, do: where(query, [a], a.status in ^statuses), else: query
    end)
    |> order_by([a], asc: a.queued_at, asc: a.id)
    |> Repo.all()
  end

  @impl true
  def attendee_counts(_context, []), do: %{}

  def attendee_counts(_context, event_ids) do
    EventAttendee
    |> where([a], a.event_id in ^event_ids and a.status in ["going", "waitlisted"])
    |> group_by([a], [a.event_id, a.status])
    |> select([a], {a.event_id, a.status, count(a.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {event_id, status, count}, acc ->
      Map.update(acc, event_id, %{status => count}, &Map.put(&1, status, count))
    end)
  end

  @impl true
  def count_guests(_context, event_id, inviter_id) do
    EventAttendee
    |> where(
      [a],
      a.event_id == ^event_id and a.invited_by_id == ^inviter_id and
        a.status in ["going", "waitlisted"]
    )
    |> select([a], count(a.id))
    |> Repo.one()
  end

  @impl true
  def insert_attendee(_context, attrs),
    do: attrs |> EventAttendee.create_changeset() |> Repo.insert()

  @impl true
  def update_attendee(_context, attendee, attrs),
    do: attendee |> EventAttendee.update_changeset(attrs) |> Repo.update()

  @impl true
  def attendances_of(_context, user_id, statuses) do
    EventAttendee
    |> where([a], a.user_id == ^user_id and a.status in ^statuses)
    |> Repo.all()
  end

  @impl true
  def late_cancel_counts(_context, [], _since), do: %{}

  def late_cancel_counts(%{organization_id: organization_id}, user_ids, since) do
    EventAttendee
    |> where(
      [a],
      a.organization_id == ^organization_id and a.user_id in ^user_ids and a.late_cancel and
        a.cancelled_at >= ^since
    )
    |> group_by([a], a.user_id)
    |> select([a], {a.user_id, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def mark_converted(%{organization_id: organization_id}, user_id, %{from: from, to: to}, at) do
    events =
      from e in Event,
        where:
          e.organization_id == ^organization_id and is_nil(e.cancelled_at) and
            e.ends_at >= ^from and e.ends_at <= ^to,
        select: e.id

    EventAttendee
    |> where(
      [a],
      a.organization_id == ^organization_id and a.user_id == ^user_id and a.status == "going" and
        not is_nil(a.checked_in_at) and is_nil(a.converted_at) and a.event_id in subquery(events)
    )
    |> Repo.update_all(set: [converted_at: at, updated_at: at])
    |> elem(0)
  end
end
