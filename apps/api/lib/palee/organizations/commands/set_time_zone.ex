defmodule Palee.Organizations.Commands.SetTimeZone do
  @moduledoc """
  ADR-176: an owner or admin confirms the gym's time zone, or the app reports
  a guess from their device. A guess never replaces a confirmed zone.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{TenantAuthorization, TimeZonePolicy}
  alias Palee.Organizations.OrganizationStore

  def call(context, zone, source) do
    with :ok <- TenantAuthorization.authorize(context, [:owner, :admin]),
         :ok <- valid(zone, source) do
      RepoContext.run(context, fn ->
        OrganizationStore.put_organization_timezone(context.organization_id, zone, source)
      end)
    end
  end

  defp valid(zone, source) do
    cond do
      source not in TimeZonePolicy.sources() -> {:error, :invalid_time_zone}
      not TimeZonePolicy.valid?(zone) -> {:error, :invalid_time_zone}
      true -> :ok
    end
  end
end
