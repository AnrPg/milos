defmodule Palee.Application.ListGymStaff do
  @moduledoc """
  The gym's staff by their role in this gym (ADR-098), for coach pickers in
  packages and appointments.
  """

  alias Palee.{Identity, Organizations}

  def call(%{organization_id: organization_id}) do
    staff = Organizations.list_staff(organization_id)
    users = staff |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    staff
    |> Enum.filter(&Map.has_key?(users, &1.user_id))
    |> Enum.map(fn %{user_id: user_id, role: role} ->
      %{user_id: user_id, role: role, nickname: Map.fetch!(users, user_id).nickname}
    end)
    |> Enum.sort_by(&String.downcase(&1.nickname || ""))
  end
end
