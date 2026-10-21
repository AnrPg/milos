defmodule Palee.Application.ListAdminWorkouts do
  alias Palee.Workouts

  def call(context), do: {:ok, Workouts.list_workouts(context)}
end
