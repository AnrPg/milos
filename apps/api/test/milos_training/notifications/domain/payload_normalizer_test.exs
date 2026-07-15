defmodule MilosTraining.Notifications.Domain.PayloadNormalizerTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Notifications.Domain.PayloadNormalizer

  describe "normalize/1" do
    test "stringifies atom keys and nested dates" do
      payload = %{
        assignment_id: "assignment-1",
        from_date: ~D[2026-06-10],
        nested: %{
          to_date: ~D[2026-06-11],
          sent_at: ~U[2026-06-11 12:00:00Z]
        },
        history: [%{scheduled_for: ~D[2026-06-12]}]
      }

      assert PayloadNormalizer.normalize(payload) == %{
               "assignment_id" => "assignment-1",
               "from_date" => "2026-06-10",
               "nested" => %{
                 "to_date" => "2026-06-11",
                 "sent_at" => "2026-06-11T12:00:00Z"
               },
               "history" => [%{"scheduled_for" => "2026-06-12"}]
             }
    end
  end
end
