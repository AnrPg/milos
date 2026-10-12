defmodule MilosTraining.Application.ListClassSlotInjuryWarnings do
  @moduledoc """
  Staff use case (ADR-114): injury warnings for the members booked
  (pending or approved) into a class slot, against the slot's workout.
  A slot without a workout has nothing to warn about.
  """

  alias MilosTraining.Application.EvaluateAthleteInjuryWarnings
  alias MilosTraining.Scheduling

  @booked_statuses ["approved", "pending"]

  def call(%{organization_id: organization_id} = context, slot_id)
      when is_binary(organization_id) do
    with {:ok, slot} <- fetch_slot(context, slot_id) do
      evaluate(context, slot)
    end
  end

  def call(_context, _slot_id), do: {:error, :organization_context_required}

  defp evaluate(_context, %{master_workout_id: nil} = slot),
    do: {:ok, %{slot_id: slot.id, workout_id: nil, level: :none, athletes: []}}

  defp evaluate(context, slot) do
    user_ids =
      slot.bookings
      |> Enum.filter(&(to_string(&1.status) in @booked_statuses))
      |> Enum.map(& &1.user_id)

    with {:ok, result} <-
           EvaluateAthleteInjuryWarnings.call(context, %{
             workout_id: slot.master_workout_id,
             user_ids: user_ids,
             surface: "class_roster",
             source_context_id: slot.id
           }) do
      {:ok, Map.put(result, :slot_id, slot.id)}
    end
  end

  defp fetch_slot(context, slot_id) do
    case Ecto.UUID.cast(slot_id) do
      {:ok, slot_id} ->
        case Scheduling.get_slot(context, slot_id) do
          %{id: _id} = slot -> {:ok, slot}
          _missing -> {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end
end
