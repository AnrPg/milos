defmodule Palee.Workouts.Domain.WorkoutAuthoringMetadataTimerInferenceTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.WorkoutAuthoringMetadata

  test "accepts the free-text timer inference flag" do
    assert :ok =
             WorkoutAuthoringMetadata.validate(:workout, %{"timer_inference" => "complete"})

    assert :ok =
             WorkoutAuthoringMetadata.validate(:workout, %{"timer_inference" => "incomplete"})

    assert {:error, _} =
             WorkoutAuthoringMetadata.validate(:workout, %{"timer_inference" => "maybe"})
  end
end
