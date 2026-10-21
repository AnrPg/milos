defmodule Palee.Scaling.DomainTest do
  @moduledoc "ADR-174: advisor input, answer validation and the suggestion lifecycle (pure)."

  use ExUnit.Case, async: true

  alias Palee.AiUsage.Domain.AiSettingsPolicy
  alias Palee.Execution
  alias Palee.Scaling.Domain.{Advice, AdvisorInput, SuggestionPolicy}

  @workout %{
    title: "Legs",
    type: :crossfit,
    sections: [
      %{
        id: "s1",
        name: "Strength",
        exercises: [
          %{id: "e0", name: "Warm-up", item_type: "header"},
          %{
            id: "e1",
            name: "Back Squat",
            sets: 5,
            prescription_value: 5,
            prescription_unit: "reps"
          },
          %{id: "e2", name: "Strict Press", prescription_value: 8, prescription_unit: "reps"}
        ]
      }
    ]
  }

  @levels [%{slug: "scaled", label: "Scaled"}, %{slug: "rx", label: "Rx"}]

  describe "AdvisorInput" do
    test "keeps the workout's own ids and leaves headers and identities out" do
      input =
        AdvisorInput.build(%{
          workout: @workout,
          injuries: [
            %{
              id: "injury-uuid-77",
              user_id: "athlete-id",
              body_area: "knee",
              severity: "moderate",
              tags: [],
              training_limitations: nil
            }
          ],
          warnings: [%{regions: [:knee], exercises: [%{name: "Back Squat", level: :avoid}]}],
          scale_levels: @levels,
          history: []
        })

      assert [%{id: "e1", section_id: "s1", prescription: "5 sets · 5 reps"}, %{id: "e2"}] =
               AdvisorInput.movements(@workout)

      assert input.flagged_movements == [%{name: "Back Squat", level: "avoid"}]
      refute inspect(input) =~ "athlete-id"
      refute inspect(input) =~ "injury-uuid-77"
      assert input.locale == "el"
    end

    test "free text reads line by line" do
      assert [
               %{id: "line-1", section_id: "free-text", name: "21-15-9 thrusters"},
               %{id: "line-2"}
             ] =
               AdvisorInput.movements(%{
                 sections: [],
                 free_text_body: "21-15-9 thrusters\n\npull-ups"
               })
    end

    test "the digest ignores history and key order" do
      base = %{workout: @workout, injuries: [], warnings: [], scale_levels: @levels}
      a = AdvisorInput.build(Map.put(base, :history, []))
      b = AdvisorInput.build(Map.put(base, :history, [%{movement: "x"}]))
      assert AdvisorInput.digest(a) == AdvisorInput.digest(b)

      c = AdvisorInput.build(%{base | injuries: [%{body_area: "knee"}]})
      refute AdvisorInput.digest(a) == AdvisorInput.digest(c)
    end
  end

  describe "Advice" do
    test "keeps valid changes to existing movements only" do
      raw = %{
        "summary" => " Ήπια ",
        "scale_level" => "rx-plus",
        "items" => [
          %{
            "exercise_id" => "e1",
            "change" => "substitute",
            "suggested" => "Box squat",
            "reason" => "Λιγότερο βάθος."
          },
          %{"exercise_id" => "e1", "change" => "load", "suggested" => "60%", "reason" => "dup"},
          %{"exercise_id" => "ghost", "change" => "skip", "reason" => "x"},
          %{"exercise_id" => "e2", "change" => "teleport", "suggested" => "?", "reason" => "x"},
          %{"exercise_id" => "e2", "change" => "load", "suggested" => nil, "reason" => "x"}
        ]
      }

      assert {:ok, %{summary: "Ήπια", scale_level_slug: nil, items: [item]}} =
               Advice.normalize(raw, AdvisorInput.movements(@workout), @levels)

      assert %{id: "i1", exercise_id: "e1", exercise_name: "Back Squat", change: "substitute"} =
               item
    end

    test "nothing to change, and malformed answers" do
      assert {:ok, :no_change} = Advice.normalize(%{"items" => []}, [], @levels)

      assert {:ok, %{scale_level_slug: "scaled", items: []}} =
               Advice.normalize(%{"items" => [], "scale_level" => "scaled"}, [], @levels)

      assert {:error, :advisor_invalid_response} = Advice.normalize(%{"x" => 1}, [], @levels)
    end
  end

  describe "SuggestionPolicy" do
    defp pending do
      {:ok, advice} =
        Advice.normalize(
          %{
            "scale_level" => "scaled",
            "items" => [
              %{
                "exercise_id" => "e1",
                "change" => "substitute",
                "suggested" => "Box squat",
                "reason" => "r1"
              },
              %{"exercise_id" => "e2", "change" => "skip", "reason" => "r2"}
            ]
          },
          AdvisorInput.movements(@workout),
          @levels
        )

      %{
        id: "sug",
        status: "pending",
        items: advice.items,
        scale_level_slug: advice.scale_level_slug
      }
    end

    test "approval with edits yields valid ADR-050 patches" do
      now = ~U[2026-10-21 10:00:00Z]

      assert {:ok, changes} =
               SuggestionPolicy.approve(
                 pending(),
                 %{
                   items: [%{id: "i1", suggested: "Goblet squat"}, %{id: "i2", include: false}],
                   coach_note: " ok "
                 },
                 "coach",
                 now
               )

      assert changes.status == "approved"
      assert changes.coach_note == "ok"
      assert [%{suggested: "Goblet squat"}] = changes.items
      assert [patch] = changes.modifications
      assert patch["patch_id"] == "scaling-sug-i1"
      assert {:ok, _} = Execution.normalize_modification(patch)
    end

    test "every change kind is a valid patch" do
      items =
        for {change, id} <- Enum.with_index(~w(substitute load reps skip other)) do
          %{
            id: "i#{id}",
            exercise_id: "e1",
            section_id: "s1",
            exercise_name: "Back Squat",
            prescribed: "5 reps",
            change: change,
            suggested: "3 reps",
            reason: "r"
          }
        end

      for patch <- SuggestionPolicy.patches("s", items) do
        assert {:ok, _} = Execution.normalize_modification(patch)
      end
    end

    test "nothing left, double review and the member's view" do
      assert {:error, :nothing_to_approve} =
               SuggestionPolicy.approve(
                 pending(),
                 %{
                   items: [%{id: "i1", include: false}, %{id: "i2", include: false}],
                   scale_level_slug: nil
                 },
                 "c",
                 DateTime.utc_now()
               )

      assert {:error, :already_reviewed} =
               SuggestionPolicy.approve(%{status: "approved"}, %{}, "c", DateTime.utc_now())

      assert {:error, :already_reviewed} =
               SuggestionPolicy.dismiss(%{status: "dismissed"}, "c", DateTime.utc_now())

      assert SuggestionPolicy.member_view(pending()) == nil
    end

    test "regeneration respects the coach's decision" do
      assert SuggestionPolicy.next_step(nil, "d") == :generate
      assert SuggestionPolicy.next_step(%{status: "approved", input_digest: "x"}, "d") == :skip
      assert SuggestionPolicy.next_step(%{status: "dismissed", input_digest: "x"}, "d") == :skip
      assert SuggestionPolicy.next_step(%{status: "pending", input_digest: "d"}, "d") == :skip

      assert {:replace, _} =
               SuggestionPolicy.next_step(%{status: "pending", input_digest: "x"}, "d")

      assert {:replace, _} =
               SuggestionPolicy.next_step(%{status: "no_change", input_digest: "x"}, "d")
    end
  end

  describe "AiSettingsPolicy" do
    test "feature runs only when on, keyed and not rejected" do
      refute AiSettingsPolicy.scaling_ready?(nil)

      refute AiSettingsPolicy.scaling_ready?(%{
               scaling_enabled: true,
               api_key: nil,
               key_status: "unknown"
             })

      refute AiSettingsPolicy.scaling_ready?(%{
               scaling_enabled: true,
               api_key: "k",
               key_status: "rejected"
             })

      assert AiSettingsPolicy.scaling_ready?(%{
               scaling_enabled: true,
               api_key: "k",
               key_status: "valid"
             })
    end

    test "validates keys and models; never exposes the key" do
      assert {:error, :invalid_api_key} =
               AiSettingsPolicy.update_changes(nil, %{api_key: "short"}, "a")

      assert {:error, :invalid_model} =
               AiSettingsPolicy.update_changes(nil, %{model: "Bad Model!"}, "a")

      assert {:ok, %{model: nil}} = AiSettingsPolicy.update_changes(nil, %{model: " "}, "a")

      public = AiSettingsPolicy.public(%{api_key: "secret-key-value", api_key_last4: "alue"}, "m")
      refute inspect(public) =~ "secret-key-value"
      assert public.key_configured
    end
  end
end
