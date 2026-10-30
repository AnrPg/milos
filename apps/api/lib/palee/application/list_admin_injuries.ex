defmodule Palee.Application.ListAdminInjuries do
  @moduledoc """
  The gym's injury list (ADR-286): a coach sees their own clients, owners,
  admins and head coaches everyone; members' shared self-reports included.
  Each read is logged for the members it shows.
  """

  alias Palee.Application.StaffInjuryAccess
  alias Palee.Wellbeing

  def call(context, params) do
    filters =
      StaffInjuryAccess.scope_filters(
        context,
        Map.new(params, fn {k, v} -> {to_string(k), v} end)
      )

    Palee.Wellbeing.WellbeingStore.with_context(context, fn ->
      injuries = Wellbeing.list_injuries(filters)
      StaffInjuryAccess.log_reads(context, "box_list", injuries)
      {:ok, %{injuries: Enum.map(injuries, &with_owner/1)}}
    end)
  end

  def call(params), do: {:ok, %{injuries: Wellbeing.list_injuries(params)}}

  defp with_owner(injury),
    do: Map.put(injury, :owned_by_member, StaffInjuryAccess.owned_by_member?(injury))
end
