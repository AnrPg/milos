defmodule Palee.Application.SetStaffLocationScope do
  @moduledoc """
  Admin › Χρήστες: the branches someone works at as staff (ADR-186). The
  requested branches are checked against the gym's active locations here;
  Organizations decides who may set them and within which scope.
  """

  alias Palee.{Facility, Organizations}

  @doc "`params`: `all_locations: true` or `location_ids: [...]`."
  def call(context, user_id, params) do
    known = context |> Facility.list_locations() |> Enum.map(& &1.id)

    with {:ok, scope} <- Organizations.parse_location_scope(params || %{}, known),
         {:ok, result} <- Organizations.set_membership_location_scope(context, user_id, scope) do
      {:ok,
       %{
         user_id: result.membership.user_id,
         location_scope: Organizations.location_scope_payload(result.location_scope)
       }}
    end
  end
end
