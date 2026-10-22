defmodule Palee.Workouts.Domain.SectionedTextTest do
  use ExUnit.Case, async: true

  alias Palee.Workouts.Domain.SectionedText

  defp section(attrs) do
    Map.merge(
      %{
        "name" => "Strength",
        "free_text_body" => "Back squat 5x5",
        "timer_preset" => %{"format" => "emom", "interval_seconds" => 90, "rounds" => 5}
      },
      attrs
    )
  end

  defp params(sections),
    do: %{
      "authoring_mode" => "sectioned_text",
      "sections" => sections,
      "workout_metadata" => %{"free_text_timer" => %{"format" => "amrap"}, "objective" => "x"}
    }

  test "composes the workout's text and rich text from titled and untitled sections" do
    assert {:ok, prepared} =
             SectionedText.prepare_publish(
               params([
                 section(%{}),
                 section(%{
                   "name" => "  ",
                   "free_text_body" => " 21-15-9\nThrusters ",
                   "timer_preset" => %{"format" => "for_time", "duration_seconds" => 600}
                 })
               ])
             )

    assert prepared["free_text_body"] == "Strength\nBack squat 5x5\n\n21-15-9\nThrusters"

    assert [first, second] = prepared["sections"]
    assert first["name"] == "Strength"
    assert first["order"] == 1
    assert first["exercises"] == []
    assert first["timer_preset"]["format"] == "emom"
    assert first["timer_preset"]["interval_seconds"] == 90
    assert second["name"] == "2"
    assert second["section_metadata"] == %{"untitled" => true}

    assert [
             %{"type" => "heading", "content" => [%{"text" => "Strength"}]},
             %{"type" => "paragraph"},
             %{"type" => "paragraph", "content" => [%{"text" => "21-15-9"}]},
             %{"type" => "paragraph", "content" => [%{"text" => "Thrusters"}]}
           ] = prepared["free_text_document"]["content"]

    # The sections time the workout; a whole-workout timer would contradict them.
    assert prepared["workout_metadata"] == %{"objective" => "x"}
  end

  test "keeps the editor's own document for a section" do
    document = %{"type" => "doc", "content" => [%{"type" => "bulletList", "content" => []}]}

    assert {:ok, %{"sections" => [prepared]}} =
             SectionedText.prepare_publish(params([section(%{"free_text_document" => document})]))

    assert prepared["free_text_document"] == document
  end

  test "names every section that lacks its text or a timer" do
    assert {:error, {:invalid_text_sections, problems}} =
             SectionedText.prepare_publish(
               params([
                 section(%{}),
                 section(%{"free_text_body" => "  "}),
                 section(%{"timer_preset" => nil}),
                 section(%{"timer_preset" => %{"format" => "rocket"}})
               ])
             )

    assert problems == [
             %{section: 2, problem: "text_required"},
             %{section: 3, problem: "timer_required"},
             %{section: 4, problem: "timer_required"}
           ]
  end

  test "the stopwatch counts as a timer" do
    assert {:ok, %{"sections" => [%{"timer_preset" => %{"format" => "untimed"}}]}} =
             SectionedText.prepare_publish(
               params([section(%{"timer_preset" => %{"format" => "untimed"}})])
             )
  end

  test "rejects a workout without sections or with too many" do
    assert {:error, :no_sections} = SectionedText.prepare_publish(params([]))

    too_many = List.duplicate(section(%{}), SectionedText.max_sections() + 1)

    assert {:error, {:invalid_text_sections, [%{problem: "too_many_sections"}]}} =
             SectionedText.prepare_publish(params(too_many))
  end

  test "bounds a section's text and title" do
    long_text = String.duplicate("a", SectionedText.max_body_bytes() + 1)

    assert {:error, {:invalid_text_sections, problems}} =
             SectionedText.prepare_publish(
               params([
                 section(%{"free_text_body" => long_text, "name" => String.duplicate("t", 121)})
               ])
             )

    assert %{section: 1, problem: "text_too_long"} in problems
    assert %{section: 1, problem: "title_too_long"} in problems
  end
end
