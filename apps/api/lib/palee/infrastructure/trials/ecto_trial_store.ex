defmodule Palee.Infrastructure.Trials.EctoTrialStore do
  @moduledoc "Ecto adapter of trial policies and requests (ADR-144)."

  @behaviour Palee.Trials.Ports.TrialStore

  import Ecto.Query

  alias Palee.Repo
  alias Palee.Trials.{TrialPolicy, TrialRequest}
  alias Palee.Trials.Domain.TrialLifecycle

  @impl true
  def get_policy(%{organization_id: organization_id}),
    do: Repo.get_by(TrialPolicy, organization_id: organization_id)

  @impl true
  def put_policy(%{organization_id: organization_id}, attrs) do
    (Repo.get_by(TrialPolicy, organization_id: organization_id) ||
       TrialPolicy.default(organization_id))
    |> TrialPolicy.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @impl true
  def insert_request(_context, attrs),
    do: attrs |> TrialRequest.create_changeset() |> Repo.insert()

  @impl true
  def get_request(_context, id), do: Repo.get(TrialRequest, id)

  @impl true
  def get_request_by_booking(_context, booking_id),
    do: Repo.get_by(TrialRequest, booking_id: booking_id)

  @impl true
  def get_request_by_operation(_context, user_id, operation_id),
    do: Repo.get_by(TrialRequest, user_id: user_id, client_operation_id: operation_id)

  @impl true
  def update_request(_context, request, changes),
    do: request |> TrialRequest.transition_changeset(changes) |> Repo.update()

  @impl true
  def list_requests(%{organization_id: organization_id}, filters) do
    TrialRequest
    |> where([r], r.organization_id == ^organization_id)
    |> statuses(Map.get(filters, :statuses))
    |> person(Map.get(filters, :user_id))
    |> class(Map.get(filters, :scheduled_class_id))
    |> window(Map.get(filters, :from), Map.get(filters, :to))
    |> order(Map.get(filters, :statuses))
    |> limit(^Map.get(filters, :limit, 200))
    |> Repo.all()
  end

  @impl true
  def list_person_requests(_context, user_id, opts) do
    TrialRequest
    |> where([r], r.user_id == ^user_id)
    |> window(Map.get(opts, :since), nil)
    |> order_by([r], desc: r.class_starts_at)
    |> limit(50)
    |> Repo.all()
  end

  @impl true
  def person_statuses(%{organization_id: organization_id}, user_id) do
    TrialRequest
    |> where([r], r.organization_id == ^organization_id and r.user_id == ^user_id)
    |> select([r], r.status)
    |> Repo.all()
  end

  @impl true
  def count_in_window(%{organization_id: organization_id}, %{from: from, to: to}, statuses) do
    TrialRequest
    |> where([r], r.organization_id == ^organization_id and r.status in ^statuses)
    |> where([r], r.class_starts_at >= ^from and r.class_starts_at < ^to)
    |> Repo.aggregate(:count)
  end

  @impl true
  def open_per_class(_context, []), do: %{}

  def open_per_class(%{organization_id: organization_id}, slot_ids) do
    open = TrialLifecycle.open_statuses()

    TrialRequest
    |> where([r], r.organization_id == ^organization_id and r.scheduled_class_id in ^slot_ids)
    |> where([r], r.status in ^open)
    |> group_by([r], r.scheduled_class_id)
    |> select([r], {r.scheduled_class_id, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def stats(%{organization_id: organization_id}, since) do
    TrialRequest
    |> where([r], r.organization_id == ^organization_id and r.class_starts_at >= ^since)
    |> group_by([r], r.status)
    |> select([r], {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @impl true
  def referral_event_stats(_context, []), do: %{}

  def referral_event_stats(%{organization_id: organization_id}, event_ids) do
    TrialRequest
    |> where(
      [r],
      r.organization_id == ^organization_id and r.referral_event_id in ^event_ids
    )
    |> group_by([r], [r.referral_event_id, r.status])
    |> select([r], {r.referral_event_id, r.status, count(r.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {event_id, status, count}, acc ->
      Map.update(acc, event_id, %{status => count}, &Map.put(&1, status, count))
    end)
  end

  # A transaction-scoped advisory lock per box: concurrent asks for the same
  # box queue here, so seat, weekly and per-person limits are never overrun.
  @impl true
  def with_box_lock(%{organization_id: organization_id}, fun) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 144))", [
        "trials:" <> organization_id
      ])

      case fun.() do
        {:error, reason} -> Repo.rollback(reason)
        {:error, reason, details} -> Repo.rollback({reason, details})
        result -> result
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, {reason, details}} when is_atom(reason) -> {:error, reason, details}
      {:error, reason} -> {:error, reason}
    end
  end

  defp person(query, nil), do: query
  defp person(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp class(query, nil), do: query
  defp class(query, slot_id), do: where(query, [r], r.scheduled_class_id == ^slot_id)

  defp statuses(query, nil), do: query
  defp statuses(query, list), do: where(query, [r], r.status in ^list)

  defp window(query, nil, nil), do: query
  defp window(query, from, nil), do: where(query, [r], r.class_starts_at >= ^from)
  defp window(query, nil, to), do: where(query, [r], r.class_starts_at < ^to)

  defp window(query, from, to),
    do: where(query, [r], r.class_starts_at >= ^from and r.class_starts_at < ^to)

  # Upcoming work reads soonest first; history reads newest first.
  defp order(query, statuses) when is_list(statuses) do
    if Enum.all?(statuses, &TrialLifecycle.open?/1),
      do: order_by(query, [r], asc: r.class_starts_at),
      else: order_by(query, [r], desc: r.class_starts_at)
  end

  defp order(query, _statuses), do: order_by(query, [r], desc: r.class_starts_at)
end
