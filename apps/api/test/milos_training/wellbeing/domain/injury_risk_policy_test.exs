defmodule MilosTraining.Wellbeing.Domain.InjuryRiskPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Wellbeing.Domain.InjuryRiskPolicy
  alias MilosTraining.Workouts.Domain.WorkoutDsl.ExerciseCatalog

  defp injury(attrs) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        organization_id: Ecto.UUID.generate(),
        body_area: "knee",
        severity: "moderate",
        status: "active",
        tags: [],
        training_limitations: nil
      },
      attrs
    )
  end

  defp exercise(name, ref \\ nil, category \\ nil),
    do: %{name: name, exercise_ref: ref, category: category}

  describe "catalog mapping" do
    test "every Quick Text catalog exercise has a curated, code-owned mapping decision" do
      mapped = InjuryRiskPolicy.catalog_patterns()

      missing =
        ExerciseCatalog.entries()
        |> Enum.map(& &1.id)
        |> Enum.reject(&Map.has_key?(mapped, &1))

      assert missing == [], "unmapped catalog ids: #{inspect(missing)}"
    end

    test "mapping keys only reference real catalog ids" do
      catalog_ids = MapSet.new(ExerciseCatalog.entries(), & &1.id)

      assert InjuryRiskPolicy.catalog_patterns()
             |> Map.keys()
             |> Enum.reject(&MapSet.member?(catalog_ids, &1)) == []
    end

    test "catalog ids win over name heuristics" do
      assert {patterns, :catalog} =
               InjuryRiskPolicy.exercise_patterns(exercise("Whatever label", "back-squat"))

      assert :squat in patterns
      assert :spinal_load in patterns
    end

    test "names fall back to heuristics when there is no catalog id" do
      assert {patterns, :name} = InjuryRiskPolicy.exercise_patterns(exercise("Air Squats"))
      assert :squat in patterns

      assert {patterns, :name} = InjuryRiskPolicy.exercise_patterns(exercise("Barbell Row"))
      assert :horizontal_pull in patterns
      refute :rowing_erg in patterns

      assert {patterns, :name} = InjuryRiskPolicy.exercise_patterns(exercise("Row 500m"))
      assert patterns == [:rowing_erg]

      assert {patterns, :name} = InjuryRiskPolicy.exercise_patterns(exercise("Lying Leg Curl"))
      assert :hamstring_curl in patterns
      refute :elbow_flexion in patterns

      assert {[], :unmatched} = InjuryRiskPolicy.exercise_patterns(exercise("Mystery Thing"))
    end
  end

  describe "body area recognition" do
    test "free-text body areas resolve to canonical regions (incl. plurals, Greek)" do
      assert InjuryRiskPolicy.regions_for("Left knee") == [:knee]
      assert InjuryRiskPolicy.regions_for("shoulders") == [:shoulder]
      assert InjuryRiskPolicy.regions_for("Lower back") == [:back]
      assert InjuryRiskPolicy.regions_for("Γόνατο") == [:knee]
      assert InjuryRiskPolicy.regions_for("knee and ankle") == [:knee, :ankle]
      assert InjuryRiskPolicy.regions_for("spleen") == []
    end

    # TD-088: every UI locale (ar bg de el en es fr he it nl pt-PT ru).
    test "body areas resolve in every supported UI locale" do
      cases = [
        # Spanish
        {"Rodilla derecha", [:knee]},
        {"hombro izquierdo", [:shoulder]},
        {"Muñeca", [:wrist]},
        {"dolor de espalda baja", [:back]},
        {"tobillo", [:ankle]},
        {"isquiotibiales", [:hamstring]},
        # French
        {"Épaule droite", [:shoulder]},
        {"genou", [:knee]},
        {"cheville", [:ankle]},
        {"bas du dos", [:back]},
        {"poignet", [:wrist]},
        # German
        {"Schulter", [:shoulder]},
        {"Rücken", [:back]},
        {"Kniescheibe", [:knee]},
        {"Sprunggelenk", [:ankle]},
        {"Hüfte", [:hip]},
        {"Ellenbogen", [:elbow]},
        # Italian
        {"Ginocchio sinistro", [:knee]},
        {"spalla", [:shoulder]},
        {"caviglia", [:ankle]},
        {"gomito", [:elbow]},
        # Portuguese
        {"Joelho", [:knee]},
        {"ombro", [:shoulder]},
        {"tornozelo", [:ankle]},
        {"cotovelo", [:elbow]},
        {"pescoço", [:neck]},
        # Dutch
        {"Knie", [:knee]},
        {"schouder", [:shoulder]},
        {"enkel", [:ankle]},
        {"pols", [:wrist]},
        {"onderrug", [:back]},
        # Russian
        {"Колено", [:knee]},
        {"плечо", [:shoulder]},
        {"поясница", [:back]},
        {"голеностоп", [:ankle]},
        {"шея", [:neck]},
        # Bulgarian
        {"Коляно", [:knee]},
        {"рамо", [:shoulder]},
        {"глезен", [:ankle]},
        {"кръст", [:back]},
        # Arabic (with and without the definite article)
        {"الركبة", [:knee]},
        {"ركبة", [:knee]},
        {"الكتف", [:shoulder]},
        {"أسفل الظهر", [:back]},
        {"الكاحل", [:ankle]},
        # Hebrew (with and without the definite article)
        {"הברך", [:knee]},
        {"כתף", [:shoulder]},
        {"גב תחתון", [:back]},
        {"קרסול", [:ankle]}
      ]

      for {body_area, regions} <- cases do
        assert InjuryRiskPolicy.regions_for(body_area) == regions,
               "#{body_area} should resolve to #{inspect(regions)}"
      end
    end

    test "short or ambiguous synonyms only match whole words" do
      # "pie" (es: foot) must not match "pierna" (leg); "dos" (fr: back) must
      # not match "dose"; "main" (fr: hand) must not match "maintenance".
      assert InjuryRiskPolicy.regions_for("pierna") == []
      assert InjuryRiskPolicy.regions_for("dose") == []
      assert InjuryRiskPolicy.regions_for("maintenance") == []
      assert InjuryRiskPolicy.regions_for("pie izquierdo") == [:ankle]
      assert InjuryRiskPolicy.regions_for("dos") == [:back]
      assert InjuryRiskPolicy.regions_for("main droite") == [:wrist]
    end
  end

  describe "evaluate/2" do
    test "a moderate knee injury marks squats and jumps avoid and running caution" do
      knee =
        injury(%{
          body_area: "knee",
          severity: "moderate",
          training_limitations: "No deep flexion"
        })

      result =
        InjuryRiskPolicy.evaluate([knee], [
          exercise("Back Squat", "back-squat", "strength"),
          exercise("Box Jump", "box-jump", "bodyweight"),
          exercise("Run", "run", "cardio"),
          exercise("Strict Press", "strict-press", "strength")
        ])

      assert result.level == :avoid
      assert [warning] = result.warnings
      assert warning.injury_id == knee.id
      assert warning.level == :avoid
      assert warning.regions == [:knee]
      assert warning.training_limitations == "No deep flexion"
      assert warning.provenance == :organization

      levels = Map.new(warning.exercises, &{&1.exercise_ref, &1.level})
      assert levels == %{"back-squat" => :avoid, "box-jump" => :avoid, "run" => :caution}
    end

    test "a mild injury only cautions primary patterns and ignores secondary ones" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{severity: "mild"})], [
          exercise("Back Squat", "back-squat"),
          exercise("Run", "run")
        ])

      assert result.level == :caution
      assert [%{exercises: [%{exercise_ref: "back-squat", level: :caution}]}] = result.warnings
    end

    test "a severe injury avoids secondary patterns too" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{severity: "severe"})], [exercise("Run", "run")])

      assert [%{level: :avoid, exercises: [%{level: :avoid}]}] = result.warnings
    end

    test "mobility work is capped at caution" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{severity: "severe"})], [
          exercise("Quadriceps Stretch", "quad-stretch", "mobility")
        ])

      assert [%{level: :caution, exercises: [%{level: :caution}]}] = result.warnings
    end

    test "restriction tags avoid the tagged movement regardless of body area or severity" do
      wrist = injury(%{body_area: "wrist", severity: "mild", tags: ["no-overhead", "Impact"]})

      result =
        InjuryRiskPolicy.evaluate([wrist], [
          exercise("Strict Press", "strict-press"),
          exercise("Double-under", "double-under"),
          exercise("Air Bike", "air-bike")
        ])

      levels = result.warnings |> hd() |> Map.fetch!(:exercises) |> Map.new(&{&1.name, &1.level})
      assert levels["Strict Press"] == :avoid
      assert levels["Double-under"] == :avoid
      refute Map.has_key?(levels, "Air Bike")
    end

    test "tags that name a body area add that region" do
      result =
        InjuryRiskPolicy.evaluate(
          [injury(%{body_area: "upper body", tags: ["shoulder"], severity: "moderate"})],
          [exercise("Handstand Push-up", "handstand-push-up")]
        )

      assert [%{regions: [:shoulder], level: :avoid}] = result.warnings
    end

    test "healed injuries never warn" do
      assert %{level: :none, warnings: []} =
               InjuryRiskPolicy.evaluate([injury(%{status: "healed"})], [
                 exercise("Back Squat", "back-squat")
               ])
    end

    test "an active injury whose body area is not recognised still cautions without exercises" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{body_area: "spleen", organization_id: nil})], [
          exercise("Back Squat", "back-squat")
        ])

      assert [%{level: :caution, regions: [], exercises: [], provenance: :personal}] =
               result.warnings
    end

    test "an active injury that no exercise touches produces no warning" do
      assert %{level: :none, warnings: []} =
               InjuryRiskPolicy.evaluate([injury(%{body_area: "wrist"})], [
                 exercise("Run", "run")
               ])
    end

    test "repeated exercises are reported once and headers are ignored" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{})], [
          exercise("Back Squat", "back-squat"),
          exercise("Back Squat", "back-squat"),
          %{name: "Part B", item_type: "header"}
        ])

      assert [%{exercises: [_one]}] = result.warnings
    end
  end

  describe "analytics_facts/1" do
    test "summarises a result with enums and counts only" do
      result =
        InjuryRiskPolicy.evaluate([injury(%{training_limitations: "secret free text"})], [
          exercise("Back Squat", "back-squat"),
          exercise("Run", "run")
        ])

      facts = InjuryRiskPolicy.analytics_facts(result)

      assert facts == %{
               warning_level: "avoid",
               injury_warning_count: 1,
               avoid_exercise_count: 1,
               caution_exercise_count: 1
             }

      assert InjuryRiskPolicy.analytics_facts(%{level: :none, warnings: []}) == %{
               warning_level: "none",
               injury_warning_count: 0,
               avoid_exercise_count: 0,
               caution_exercise_count: 0
             }
    end
  end
end
