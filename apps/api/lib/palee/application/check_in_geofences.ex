defmodule Palee.Application.CheckInGeofences do
  @moduledoc """
  `GET /api/me/check-in/geofences` (ADR-173): the regions the store app
  watches for the arrival reminder. For every box the member is active in
  whose owner allows it (`geofence_reminder`), the locations with a booking
  of the member whose check-in window is still ahead (`GeofencePlan`).

  Each region carries a `token` (signed, bound to the member and the
  location) that the reminder's tap sends to `POST /api/check-in/scan` as
  `geofence_token`; like the printed poster it only checks in a booking in
  its window. The phone keeps the list and decides on its own when the
  member arrives: their location never reaches the server.

  One box failing never hides the others.
  """

  require Logger

  alias Palee.Application.{CheckInFacts, MyProviders, SignedToken}
  alias Palee.{Facility, Organizations}
  alias Palee.Facility.Domain.GeofencePlan

  @token_salt "check-in-geofence-v1"
  # iOS monitors at most 20 regions per app.
  @max_regions 20
  @valid_hours 12

  def token_salt, do: @token_salt
  def token_max_age, do: (@valid_hours + 12) * 3600

  def call(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    {active, _former} =
      context |> Organizations.list_my_providers() |> Organizations.split_providers()

    regions =
      active
      |> Enum.flat_map(&provider_regions(context, &1, now))
      |> GeofencePlan.soonest(@max_regions)
      |> Enum.map(&Map.put(&1, :token, token(&1.location_id, user_id)))

    {:ok, %{regions: regions, valid_until: DateTime.add(now, @valid_hours * 3600, :second)}}
  end

  defp provider_regions(context, provider, now) do
    with {:ok, tenant} <- MyProviders.tenant_context(context, provider.organization_id),
         %{geofence_reminder: true} = rules <- Facility.check_in_rules(tenant) do
      bookings = CheckInFacts.bookings(tenant, context.user_id, now)

      tenant
      |> Facility.list_locations()
      |> GeofencePlan.regions(bookings, rules, now)
      |> Enum.map(
        &Map.merge(&1, %{
          id: "palee-" <> &1.location_id,
          organization_id: provider.organization_id,
          box_name: provider.name
        })
      )
    else
      _off -> []
    end
  rescue
    error ->
      Logger.warning(
        "geofences failed organization_id=#{provider.organization_id} reason=#{inspect(error)}"
      )

      []
  end

  defp token(location_id, user_id),
    do: SignedToken.sign(@token_salt, %{"l" => location_id, "u" => user_id})
end
