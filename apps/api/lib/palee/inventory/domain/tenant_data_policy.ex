defmodule Palee.Inventory.Domain.TenantDataPolicy do
  @moduledoc """
  Inventory tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "inventory",
            purge_order: 87,
            disposition: :purge,
            basis:
              "Machines, supplies and their event, movement and low-stock records are operational data with no retention obligation.",
            tables: [
              %{table: "inventory_machine_events"},
              %{table: "inventory_machines"},
              %{table: "inventory_supply_movements"},
              %{table: "inventory_supply_reports"},
              %{table: "inventory_supplies"}
            ]
          })

  def policy, do: @policy
end
