defmodule Palee.Application.GetWorkoutDslManual do
  @moduledoc false

  alias Palee.Workouts

  def call, do: {:ok, Workouts.dsl_manual()}
end
