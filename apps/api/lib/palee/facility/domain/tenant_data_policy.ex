defmodule Palee.Facility.Domain.TenantDataPolicy do
  @moduledoc """
  Facility tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "facility",
            purge_order: 120,
            disposition: :purge,
            basis:
              "Locations, check-ins, visitor scans, member codes and check-in rules are operational data with no retention obligation; purged after Scheduling and Appointments because classes and appointment slots reference locations.",
            tables: [
              %{table: "facility_visitor_scans"},
              %{table: "facility_member_codes"},
              %{table: "facility_check_ins"},
              %{table: "facility_check_in_settings"},
              %{table: "facility_locations"}
            ],
            # ADR-155: door and poster seeds and member-code serials are
            # credentials, never exported.
            excluded_columns: ["door_secret", "poster_secret", "serial"]
          })

  def policy, do: @policy
end
