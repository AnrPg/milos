defmodule Palee.Application.CreateAppointmentSlot do
  @moduledoc "A coach (or other staff) publishes a bookable PT session or assessment (ADR-098)."

  alias Palee.Application.ClassLocation
  alias Palee.{Appointments, Organizations}

  def call(%{organization_id: organization_id} = context, %{id: staff_id}, params) do
    coach_id = value(params, :coach_id) || staff_id

    with :ok <- staff_member(organization_id, coach_id),
         :ok <- ClassLocation.check_appointment(context, params, coach_id) do
      attrs =
        params
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.merge(%{"coach_id" => coach_id, "created_by_id" => staff_id})

      Appointments.create_slot(context, attrs)
    end
  end

  @doc """
  «Ισχύει για» (ADR-186 §8): one slot per branch of `location_ids`, created
  together or not at all; without the list, the one slot of `call/3`.
  """
  def call_at_branches(%{organization_id: organization_id} = context, %{id: staff_id} = staff, params) do
    listed? = Map.has_key?(params, :location_ids) or Map.has_key?(params, "location_ids")
    coach_id = value(params, :coach_id) || staff_id

    if listed? do
      with :ok <- staff_member(organization_id, coach_id),
           {:ok, items} <- ClassLocation.targets(context, params) do
        ClassLocation.create_all(
          context,
          items,
          &Appointments.create_slot(context, slot_attrs(&1, coach_id, staff_id)),
          &Appointments.transaction/2
        )
      end
    else
      with {:ok, slot} <- call(context, staff, params), do: {:ok, [slot]}
    end
  end

  defp slot_attrs(params, coach_id, staff_id) do
    params
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.merge(%{"coach_id" => coach_id, "created_by_id" => staff_id})
  end

  defp staff_member(organization_id, coach_id) do
    if coach_id in Organizations.list_staff_user_ids(organization_id),
      do: :ok,
      else: {:error, :appointment_coach_not_staff}
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
