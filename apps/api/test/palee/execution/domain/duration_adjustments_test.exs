defmodule Palee.Execution.Domain.DurationAdjustmentsTest do
  use ExUnit.Case, async: true

  alias Palee.Execution.Domain.DurationAdjustments

  @segments [
    %{
      segment_key: "segment:0",
      section_id: "amrap",
      section_name: "AMRAP 12",
      label: "AMRAP 12",
      kind: :countdown,
      duration_seconds: 720
    },
    %{
      segment_key: "segment:1",
      section_id: "strength",
      section_name: "Strength",
      label: "Strength",
      kind: :no_timer,
      duration_seconds: nil
    }
  ]

  test "enriches adjustments with what the coach needs to read them" do
    assert DurationAdjustments.normalize(%{"segment:0" => 120}, @segments, %{}) == %{
             "segment:0" => %{
               "delta_seconds" => 120,
               "authored_seconds" => 720,
               "section_id" => "amrap",
               "section_name" => "AMRAP 12",
               "label" => "AMRAP 12"
             }
           }
  end

  test "drops untimed or unknown segments and clamps extreme values" do
    normalized =
      DurationAdjustments.normalize(
        %{"segment:0" => -5_000, "segment:1" => 30, "segment:9" => 30},
        @segments,
        %{}
      )

    assert Map.keys(normalized) == ["segment:0"]
    assert normalized["segment:0"]["delta_seconds"] == 5 - 720
  end

  test "keeps stored adjustments when the client sends none" do
    stored = %{"segment:0" => %{"delta_seconds" => 30}}
    assert DurationAdjustments.normalize(nil, @segments, stored) == stored
  end

  test "applies adjustments to the sequence" do
    [amrap, strength] =
      DurationAdjustments.apply_to(@segments, %{"segment:0" => %{"delta_seconds" => 120}})

    assert amrap.duration_seconds == 840
    assert strength.duration_seconds == nil
  end
end
