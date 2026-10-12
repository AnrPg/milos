defmodule MilosTraining.Application.CheckInOpenGym do
  @moduledoc """
  Records an open-gym visit for a member, by the member or by staff (ADR-097).
  The visit is reserved and finalized in the Finance ledger under the member's
  package, so access, location scope and the `open_gym_visits` quota apply.
  A second check-in on the same local day returns the first one unchanged.
  """

  alias MilosTraining.{Facility, Finance, Identity}
  alias MilosTraining.Facility.Domain.CheckInPolicy

  def call(context, %{id: actor_id}, user_id, params \\ %{}) do
    now = DateTime.utc_now()
    today = CheckInPolicy.local_date(now, timezone(context))
    location_id = blank_to_nil(params["location_id"] || params[:location_id])

    case Facility.get_check_in(context, user_id, today) do
      %{} = existing ->
        {:ok, Map.put(existing, :already_checked_in, true)}

      nil ->
        with %{} = member <- Identity.find_by_id(user_id) || {:error, :not_found},
             :ok <- location(context, location_id),
             id = Ecto.UUID.generate(),
             {:ok, reservation} <- reserve(context, member, id, location_id, today) do
          attrs = %{
            id: id,
            user_id: user_id,
            location_id: location_id,
            checked_in_on: today,
            checked_in_at: now,
            source: CheckInPolicy.source(actor_id, user_id),
            recorded_by_id: actor_id,
            reservation_id: reservation_id(reservation)
          }

          case Facility.create_check_in(context, attrs) do
            {:ok, check_in} ->
              finalize(context, reservation, id)
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

  defp reserve(context, member, check_in_id, location_id, today) do
    request =
      location_id
      |> CheckInPolicy.entitlement_request(today)
      |> Map.merge(%{
        actor_role: member.role,
        source_context: "facility",
        source_id: check_in_id,
        idempotency_key: CheckInPolicy.idempotency_key(member.id, today)
      })

    Finance.reserve_entitlement(context, member.id, request)
  end

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

  defp timezone(context) do
    context
    |> Finance.get_finance_settings()
    |> Map.get(:entitlement_timezone)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
