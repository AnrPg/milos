defmodule Palee.Application.CheckInOpenGym do
  @moduledoc """
  Records an open-gym visit for a member, by the member or by staff (ADR-097).
  The visit is reserved and finalized in the Finance ledger under the member's
  package, so access, location scope and the `open_gym_visits` quota apply.
  A second check-in on the same local day returns the first one unchanged.

  ADR-155 options (`params`): `method` (how it happened, default `self` for
  the member and `desk_search` for staff); `defer_finalize` keeps the visit
  reserved (not yet consumed) so a door scan can be undone within its minute,
  and `FinalizeScanCheckInJob` consumes it afterwards; `override` («Check-in
  παρ' όλα αυτά» at the desk) records the visit without touching the package.
  """

  alias Palee.{Facility, Finance, Identity, Organizations}
  alias Palee.Facility.Domain.CheckInPolicy
  alias Palee.Workers.FinalizeScanCheckInJob

  def call(context, %{id: actor_id}, user_id, params \\ %{}) do
    now = DateTime.utc_now()
    today = CheckInPolicy.local_date(now, timezone(context))
    location_id = blank_to_nil(params["location_id"] || params[:location_id])

    case Facility.get_check_in(context, user_id, today) do
      %{} = existing ->
        {:ok, Map.put(existing, :already_checked_in, true)}

      nil ->
        source = CheckInPolicy.source(actor_id, user_id)

        with %{} = member <- Identity.find_by_id(user_id) || {:error, :not_found},
             :ok <- location(context, location_id),
             id = Ecto.UUID.generate(),
             {:ok, reservation} <- reserve(context, member, id, location_id, today, params) do
          attrs = %{
            id: id,
            user_id: user_id,
            location_id: location_id,
            checked_in_on: today,
            checked_in_at: now,
            source: source,
            method: param(params, :method) || default_method(source),
            recorded_by_id: actor_id,
            reservation_id: reservation_id(reservation)
          }

          case Facility.create_check_in(context, attrs) do
            {:ok, check_in} ->
              after_check_in(context, reservation, id, param(params, :defer_finalize))
              {:ok, Map.put(check_in, :already_checked_in, false)}

            {:error, reason} ->
              release(context, reservation, id)
              {:error, reason}
          end
        end
    end
  end

  defp location(_context, nil), do: :ok

  defp location(context, location_id) do
    case Facility.get_location(context, location_id) do
      nil -> {:error, :location_not_found}
      location -> CheckInPolicy.usable_location(location)
    end
  end

  defp reserve(context, member, check_in_id, location_id, today, params) do
    if param(params, :override) == true do
      {:ok, nil}
    else
      request =
        location_id
        |> CheckInPolicy.entitlement_request(today)
        |> Map.merge(%{
          actor_role: member.role,
          source_context: "facility",
          source_id: check_in_id,
          idempotency_key: CheckInPolicy.idempotency_key(member.id, today, check_in_id)
        })

      Finance.reserve_entitlement(context, member.id, request)
    end
  end

  defp after_check_in(context, reservation, check_in_id, true) do
    case reservation_id(reservation) do
      nil -> :ok
      _id -> FinalizeScanCheckInJob.schedule(context.organization_id, check_in_id)
    end
  end

  defp after_check_in(context, reservation, check_in_id, _defer),
    do: finalize(context, reservation, check_in_id)

  @doc "Consumes the visit a deferred check-in reserved (ADR-155)."
  def finalize_deferred(context, check_in_id) do
    case Facility.get_check_in_by_id(context, check_in_id) do
      %{reservation_id: reservation_id} when is_binary(reservation_id) ->
        finalize(context, %{id: reservation_id}, check_in_id)

      _undone_or_free ->
        :ok
    end
  end

  @doc "Returns the visit of a check-in that is being undone (ADR-155)."
  def release_visit(context, %{id: check_in_id, reservation_id: reservation_id}),
    do: release(context, %{id: reservation_id}, check_in_id)

  defp default_method("self"), do: "self"
  defp default_method(_staff), do: "desk_search"

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp finalize(context, reservation, check_in_id) do
    case reservation_id(reservation) do
      nil ->
        :ok

      id ->
        _result =
          Finance.finalize_entitlement(context, id, %{
            reason: "Open gym check-in",
            idempotency_key: "open-gym-finalize:#{check_in_id}"
          })

        :ok
    end
  end

  defp release(context, reservation, check_in_id) do
    case reservation_id(reservation) do
      nil ->
        :ok

      id ->
        _result =
          Finance.release_entitlement(context, id, %{
            reason: "Check-in was not recorded",
            idempotency_key: "open-gym-release:#{check_in_id}"
          })

        :ok
    end
  end

  defp reservation_id(%{id: id}), do: id
  defp reservation_id(_reservation), do: nil

  # ADR-179: entitlement days follow the gym's own zone (one clock per gym).
  defp timezone(%{organization_id: organization_id}),
    do: Organizations.organization_timezone(organization_id)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
