defmodule MilosTraining.Pantheon.Domain.PRHistoryPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Pantheon.Domain.PRHistoryPolicy

  test "archives the prior result when its achieved date changes" do
    assert PRHistoryPolicy.snapshot_required?(%{beaten_on: ~D[2026-07-17]})
  end

  test "archives the prior result when any result context changes" do
    assert PRHistoryPolicy.snapshot_required?(%{notes: "Strict form"})
    assert PRHistoryPolicy.snapshot_required?(%{supporting_metrics: %{reps: 5}})
  end

  test "does not create a duplicate snapshot for a no-op update" do
    refute PRHistoryPolicy.snapshot_required?(%{})
  end
end
