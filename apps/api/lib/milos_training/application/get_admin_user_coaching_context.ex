defmodule MilosTraining.Application.GetAdminUserCoachingContext do
  @moduledoc false

  alias MilosTraining.Application.GetCoachingAthleteDrillDown
  alias MilosTraining.Identity
  alias MilosTraining.Identity.Domain.AdminProfilePolicy

  def call(user_id, params \\ %{}) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found} do
      if AdminProfilePolicy.coaching_available?(user.role) do
        with {:ok, %{drill_down: drill_down}} <- GetCoachingAthleteDrillDown.call(user_id, params) do
          {:ok, %{user_id: user_id, available: true, drill_down: drill_down}}
        end
      else
        {:ok, %{user_id: user_id, available: false, drill_down: nil}}
      end
    end
  end
end
