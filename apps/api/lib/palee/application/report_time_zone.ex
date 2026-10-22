defmodule Palee.Application.ReportTimeZone do
  @moduledoc """
  ADR-177: a device reports the zone its person is in, so server-written
  texts (push notifications, emails) can add "your time" beside the
  organiser's clock when the two read a moment differently. The latest
  report wins; a UTC alias says nothing about where someone is and leaves
  the stored zone as it was.
  """

  alias Palee.Identity
  alias Palee.TimeZones.ZonedTime

  def call(%{id: user_id} = user, zone) when is_binary(zone) do
    cond do
      not ZonedTime.valid?(zone) ->
        {:error, :invalid_time_zone}

      ZonedTime.utc?(zone) ->
        {:ok, Map.get(user, :time_zone)}

      true ->
        with {:ok, account} <- Identity.update_time_zone(user_id, zone),
             do: {:ok, account.time_zone}
    end
  end

  def call(_user, _zone), do: {:error, :invalid_time_zone}
end
