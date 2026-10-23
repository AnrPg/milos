defmodule Palee.Application.IssueRegistrationInvitation do
  @moduledoc """
  A gym invites someone; a staff invitation reserves a staff seat of the plan
  (ADR-170). A staff invitation may name the branches the person will work at
  (ADR-186), checked here against the gym's active locations.
  """

  alias Palee.Application.OrganizationPlan
  alias Palee.{Facility, Organizations}

  def call(context, params) do
    role = Map.get(params, :roles, Map.get(params, "roles")) || Map.get(params, :role, Map.get(params, "role"))

    with :ok <- OrganizationPlan.check_invitation(context, role),
         {:ok, params} <- with_location_scope(context, params) do
      Organizations.issue_invitation(context, params)
    end
  end

  # Only the parsed scope reaches Organizations; raw ids never do.
  defp with_location_scope(context, params) do
    params = Map.drop(params, [:location_scope, "location_scope"])

    if Organizations.location_scope_requested?(params) do
      known = context |> Facility.list_locations() |> Enum.map(& &1.id)

      with {:ok, scope} <- Organizations.parse_location_scope(params, known),
           do: {:ok, Map.put(params, :location_scope, scope)}
    else
      {:ok, params}
    end
  end
end
