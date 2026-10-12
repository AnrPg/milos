defmodule MilosTraining.Facility do
  @moduledoc """
  Facility context (ADR-097): gym locations and open-gym check-ins. Check-ins
  that consume package visits go through `Application.CheckInOpenGym`.
  """

  alias MilosTraining.Facility.FacilityStore

  def list_locations(context, opts \\ []), do: FacilityStore.list_locations(context, opts)
  def get_location(context, id), do: FacilityStore.get_location(context, id)
  def create_location(context, params), do: FacilityStore.create_location(context, params)

  def update_location(context, id, params),
    do: FacilityStore.update_location(context, id, params)

  def archive_location(context, id), do: FacilityStore.archive_location(context, id)
  def get_check_in(context, user_id, date), do: FacilityStore.get_check_in(context, user_id, date)
  def create_check_in(context, attrs), do: FacilityStore.create_check_in(context, attrs)
  def list_check_ins(context, filters \\ %{}), do: FacilityStore.list_check_ins(context, filters)
end
