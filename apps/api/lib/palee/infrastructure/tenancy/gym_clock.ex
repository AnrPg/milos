defmodule Palee.Infrastructure.Tenancy.GymClock do
  @moduledoc """
  ADR-179: "today" for the gym the current database session is scoped to.

  Store code that runs inside a tenant scope (`app.organization_id` set by
  `RepoContext.run/2`) asks this clock instead of `Date.utc_today/0`, so a
  subscription that ends "today", an invoice due "today" or the classes of
  "today" follow the gym's own midnight, not UTC's. Outside a tenant scope
  (platform jobs, a person's own cross-gym views) it falls back to UTC.

  The zone is read once per process and gym for a minute: a request or a
  job asks many times, and a zone changes rarely.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.TimeZonePolicy
  alias Palee.Organizations.OrganizationSetting
  alias Palee.Repo
  alias Palee.TimeZones.ZonedTime

  @ttl_ms 60_000

  @doc "The scoped gym's local date now; the UTC date outside a tenant scope."
  def today(now \\ DateTime.utc_now()) do
    case zone() do
      nil -> DateTime.to_date(now)
      zone -> ZonedTime.local_date(now, zone)
    end
  end

  @doc "A gym's local date now, by id."
  def today_for(organization_id, now \\ DateTime.utc_now()) when is_binary(organization_id),
    do: ZonedTime.local_date(now, zone(organization_id))

  @doc "The scoped gym's zone (the default while unknown); nil outside a tenant scope."
  def zone do
    case RepoContext.current_setting("app.organization_id") do
      nil -> nil
      organization_id -> zone(organization_id)
    end
  end

  @doc "The zone of a gym by id, cached for a minute in the calling process."
  def zone(organization_id) when is_binary(organization_id) do
    key = {__MODULE__, organization_id}
    now = System.monotonic_time(:millisecond)

    case Process.get(key) do
      {zone, at} when now - at < @ttl_ms ->
        zone

      _stale ->
        zone =
          OrganizationSetting
          |> Repo.get_by(organization_id: organization_id)
          |> TimeZonePolicy.resolve()

        Process.put(key, {zone, now})
        zone
    end
  end
end
