defmodule Palee.Application.CreateAppointmentSlot do
  @moduledoc "A coach (or other staff) publishes a bookable PT session or assessment (ADR-098)."

  alias Palee.Application.ClassLocation
  alias Palee.{Appointments, Organizations}

  def call(%{organization_id: organization_id} = context, %{id: staff_id}, params) do
    coach_id = value(params, :coach_id) || staff_id

    with :ok <- staff_member(organization_id, coach_id),
         :ok <- ClassLocation.check(context, params) do
      attrs =
        params
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.merge(%{"coach_id" => coach_id, "created_by_id" => staff_id})

      Appointments.create_slot(context, attrs)
    end
  end

  defp staff_member(organization_id, coach_id) do
    if coach_id in Organizations.list_staff_user_ids(organization_id),
      do: :ok,
      else: {:error, :appointment_coach_not_staff}
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
