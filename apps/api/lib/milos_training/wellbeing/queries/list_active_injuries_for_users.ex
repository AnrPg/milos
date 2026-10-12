defmodule MilosTraining.Wellbeing.Queries.ListActiveInjuriesForUsers do
  @moduledoc """
  Staff read (ADR-114): the active injuries of `user_ids` that carry the
  current organization's provenance. Personal (self-reported,
  organization-less) injuries and other tenants' reports are never returned,
  whatever the RLS session would otherwise allow.
  """

  alias MilosTraining.Wellbeing.WellbeingStore

  @max_users 250

  def call(user_ids) when is_list(user_ids) do
    case user_ids |> Enum.filter(&is_binary/1) |> Enum.uniq() |> Enum.take(@max_users) do
      [] -> []
      user_ids -> WellbeingStore.list_active_tenant_injuries_for_users(user_ids)
    end
  end
end
