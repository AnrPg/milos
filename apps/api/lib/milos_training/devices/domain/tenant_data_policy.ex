defmodule MilosTraining.Devices.Domain.TenantDataPolicy do
  @moduledoc """
  Device tenant data policy (ADR-117, ADR-161). A watch activity tied to a
  booked class, or merged into a gym's entry, carries that gym; a purged gym
  takes those rows with it. Connections, imports, daily stats and untied
  activities belong to the account and are never tenant data.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "devices",
            purge_order: 62,
            disposition: :purge,
            basis:
              "Heart rate and workout data from a watch are health-like data; data minimisation requires deletion once exported.",
            tables: [%{table: "device_activities", rls: :user}]
          })

  def policy, do: @policy
end
