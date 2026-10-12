defmodule MilosTraining.Wellbeing.Domain.InjuryRiskPolicy do
  @moduledoc """
  Pure mapping from a person's active injuries to non-blocking safety
  warnings for one workout (ADR-124).

  Inputs are plain maps, so this module has no dependency on the Workouts
  context:

    * injuries - `%{id, body_area, severity, status, tags, training_limitations,
      organization_id}` (the Wellbeing store's normalized shape)
    * exercises - `%{name, exercise_ref, category}` descriptors, where
      `exercise_ref` is a stable Quick Text catalog id
      (`Workouts.Domain.WorkoutDsl.ExerciseCatalog`) when one is known and
      `category` its catalog category

  Matching is two-stage. Each exercise is first reduced to movement patterns
  (`:squat`, `:overhead`, `:plyometric`, ...): the curated
  `@catalog_patterns` table keyed by catalog id wins, and name heuristics are
  the fallback for free-text exercises. Each injury is reduced to body
  regions (from its free-text `body_area` and any body-area tags), and each
  region declares the patterns that load it directly (primary) or
  indirectly (secondary). Severity scales the result:

  | severity | primary  | secondary |
  |----------|----------|-----------|
  | mild     | caution  | -         |
  | moderate | avoid    | caution   |
  | severe   | avoid    | avoid     |

  Restriction tags (`no-overhead`, `impact`, ...) always mark the restricted
  patterns `:avoid`. Mobility work is capped at `:caution`. An active injury
  whose body area cannot be recognised still produces one `:caution`
  warning with no exercises, so staff and the athlete are told to check the
  limitations rather than being silently reassured.

  Warnings inform - nothing here ever blocks an assignment, booking or
  execution.
  """

  @levels [:none, :caution, :avoid]

  @mobility_patterns [
    :shoulder_mobility,
    :hip_mobility,
    :knee_mobility,
    :ankle_mobility,
    :spine_mobility,
    :hamstring_mobility
  ]

  # Curated, code-owned mapping keyed by the stable Quick Text catalog ids.
  # A coverage test fails when the catalog gains an id without a decision
  # here; an empty list is an explicit "no injury-relevant loading" decision.
  @catalog_patterns %{
    "air-squat" => [:squat],
    "back-squat" => [:squat, :spinal_load],
    "front-squat" => [:squat, :spinal_load, :wrist_extension],
    "overhead-squat" => [:squat, :overhead, :spinal_load],
    "goblet-squat" => [:squat],
    "box-squat" => [:squat, :spinal_load],
    "split-squat" => [:lunge],
    "bulgarian-split-squat" => [:lunge],
    "pistol-squat" => [:squat, :lunge],
    "wall-sit" => [:squat],
    "deadlift" => [:hinge, :spinal_load, :grip],
    "sumo-deadlift" => [:hinge, :spinal_load, :grip],
    "romanian-deadlift" => [:hinge, :spinal_load, :grip],
    "stiff-leg-deadlift" => [:hinge, :spinal_load, :grip],
    "single-leg-deadlift" => [:hinge],
    "clean" => [:olympic, :squat, :hinge, :wrist_extension, :spinal_load],
    "power-clean" => [:olympic, :hinge, :wrist_extension, :spinal_load],
    "hang-clean" => [:olympic, :squat, :hinge, :wrist_extension, :spinal_load],
    "clean-and-jerk" => [:olympic, :squat, :hinge, :overhead, :wrist_extension, :spinal_load],
    "snatch" => [:olympic, :squat, :hinge, :overhead, :spinal_load, :grip],
    "power-snatch" => [:olympic, :hinge, :overhead, :spinal_load, :grip],
    "hang-snatch" => [:olympic, :hinge, :overhead, :spinal_load, :grip],
    "muscle-snatch" => [:olympic, :hinge, :overhead],
    "jerk" => [:olympic, :overhead, :wrist_extension, :spinal_load],
    "push-jerk" => [:olympic, :overhead, :wrist_extension, :spinal_load],
    "push-press" => [:overhead, :wrist_extension, :spinal_load],
    "strict-press" => [:overhead, :wrist_extension],
    "bench-press" => [:horizontal_push],
    "incline-bench-press" => [:horizontal_push],
    "floor-press" => [:horizontal_push],
    "dumbbell-bench-press" => [:horizontal_push],
    "dumbbell-row" => [:horizontal_pull, :grip],
    "barbell-row" => [:horizontal_pull, :hinge, :spinal_load, :grip],
    "pendlay-row" => [:horizontal_pull, :hinge, :spinal_load, :grip],
    "upright-row" => [:overhead, :grip],
    "good-morning" => [:hinge, :spinal_load],
    "hip-thrust" => [:hip_extension],
    "glute-bridge" => [:hip_extension],
    "lunge" => [:lunge],
    "reverse-lunge" => [:lunge],
    "walking-lunge" => [:lunge],
    "step-up" => [:lunge],
    "calf-raise" => [:calf],
    "biceps-curl" => [:elbow_flexion, :grip],
    "triceps-extension" => [:elbow_extension],
    "skull-crusher" => [:elbow_extension],
    "lateral-raise" => [:shoulder_isolation],
    "front-raise" => [:shoulder_isolation],
    "face-pull" => [:horizontal_pull],
    "farmer-carry" => [:carry, :grip],
    "front-rack-carry" => [:carry, :wrist_extension],
    "overhead-carry" => [:carry, :overhead],
    "sled-push" => [:sled, :calf],
    "sled-pull" => [:sled, :grip],
    "kettlebell-swing" => [:hinge, :grip],
    "american-kettlebell-swing" => [:hinge, :grip, :overhead],
    "russian-kettlebell-swing" => [:hinge, :grip],
    "turkish-get-up" => [:overhead, :lunge, :rotation, :wrist_extension],
    "thruster" => [:squat, :overhead, :wrist_extension, :spinal_load],
    "wall-ball" => [:squat, :overhead],
    "devil-press" => [:hinge, :overhead, :horizontal_push, :plyometric],
    "man-maker" => [:horizontal_push, :horizontal_pull, :squat, :overhead, :plyometric],
    "push-up" => [:horizontal_push, :wrist_extension],
    "hand-release-push-up" => [:horizontal_push, :wrist_extension],
    "diamond-push-up" => [:horizontal_push, :wrist_extension, :elbow_extension],
    "dip" => [:dip, :elbow_extension],
    "ring-dip" => [:dip, :elbow_extension],
    "pull-up" => [:vertical_pull, :hanging, :grip],
    "strict-pull-up" => [:vertical_pull, :hanging, :grip],
    "chest-to-bar-pull-up" => [:vertical_pull, :hanging, :grip],
    "chin-up" => [:vertical_pull, :hanging, :grip, :elbow_flexion],
    "ring-row" => [:horizontal_pull, :grip],
    "muscle-up" => [:vertical_pull, :hanging, :dip, :grip],
    "ring-muscle-up" => [:vertical_pull, :hanging, :dip, :grip],
    "bar-muscle-up" => [:vertical_pull, :hanging, :dip, :grip],
    "rope-climb" => [:vertical_pull, :hanging, :grip, :elbow_flexion],
    "legless-rope-climb" => [:vertical_pull, :hanging, :grip, :elbow_flexion],
    "toes-to-bar" => [:hanging, :core_flexion, :grip],
    "knees-to-elbows" => [:hanging, :core_flexion, :grip],
    "sit-up" => [:core_flexion],
    "ghd-sit-up" => [:core_flexion, :spinal_extension],
    "v-up" => [:core_flexion],
    "hollow-hold" => [:core_flexion],
    "arch-hold" => [:spinal_extension],
    "plank" => [:core_isometric],
    "side-plank" => [:core_isometric],
    "pallof-press" => [:core_isometric],
    "back-extension" => [:spinal_extension],
    "burpee" => [:plyometric, :horizontal_push, :wrist_extension, :squat],
    "burpee-box-jump" => [:plyometric, :horizontal_push, :wrist_extension, :squat],
    "box-jump" => [:plyometric, :squat],
    "box-jump-over" => [:plyometric, :squat],
    "broad-jump" => [:plyometric, :squat],
    "double-under" => [:plyometric, :calf],
    "single-under" => [:plyometric, :calf],
    "handstand-hold" => [:inversion, :overhead, :wrist_extension],
    "handstand-walk" => [:inversion, :overhead, :wrist_extension],
    "handstand-push-up" => [:inversion, :overhead, :wrist_extension],
    "wall-walk" => [:inversion, :overhead, :wrist_extension],
    "run" => [:running],
    "sprint" => [:running],
    "row" => [:rowing_erg],
    "bike" => [:cycling],
    "air-bike" => [:cycling],
    "ski-erg" => [:ski_erg],
    "swim" => [:swimming],
    "stair-climb" => [:stair_climb],
    "jumping-jack" => [:plyometric],
    "mountain-climber" => [:wrist_extension, :core_isometric],
    "bear-crawl" => [:wrist_extension, :core_isometric],
    "hip-flexor-stretch" => [:hip_mobility],
    "hamstring-stretch" => [:hamstring_mobility],
    "quad-stretch" => [:knee_mobility],
    "calf-stretch" => [:ankle_mobility],
    "pigeon-stretch" => [:hip_mobility],
    "couch-stretch" => [:hip_mobility, :knee_mobility],
    "child-pose" => [:spine_mobility, :knee_mobility],
    "downward-dog" => [:wrist_extension, :shoulder_mobility, :hamstring_mobility],
    "cat-cow" => [:spine_mobility, :wrist_extension],
    "thoracic-rotation" => [:spine_mobility],
    "shoulder-dislocate" => [:shoulder_mobility],
    "band-pull-apart" => [:shoulder_mobility],
    "foam-roll" => []
  }

  # Fallback for exercises without a catalog id. Every matching rule
  # contributes its patterns; rules are matched against the accent-free,
  # lower-cased name.
  @name_rules [
    {~r/handstand|\bhspu\b|wall walk/u, [:inversion, :overhead, :wrist_extension]},
    {~r/snatch/u, [:olympic, :hinge, :overhead, :spinal_load, :grip]},
    {~r/\bclean/u, [:olympic, :hinge, :wrist_extension, :spinal_load]},
    {~r/jerk/u, [:olympic, :overhead, :spinal_load]},
    {~r/thruster/u, [:squat, :overhead, :wrist_extension, :spinal_load]},
    {~r/overhead|shoulder press|strict press|push press|military press|\bohp\b/u, [:overhead]},
    {~r/bench|push ?ups?\b|press ?ups?\b|floor press|chest press/u, [:horizontal_push]},
    {~r/squat|wall ?balls?/u, [:squat]},
    {~r/wall ?balls?/u, [:overhead]},
    {~r/lunge|split squat|step ?ups?\b/u, [:lunge]},
    {~r/deadlift|\brdl\b|good morning|swing/u, [:hinge]},
    {~r/pull ?ups?\b|chin ?ups?\b|muscle ?ups?\b|rope climb|lat pull/u,
     [:vertical_pull, :hanging, :grip]},
    {~r/toes ?to ?bar|\bttb\b|knees ?to ?elbows|\bk2e\b|hanging/u,
     [:hanging, :core_flexion, :grip]},
    {~r/\bdips?\b/u, [:dip]},
    {~r/jump|burpee|double ?unders?|skipping|\bhops?\b|bounds?\b/u, [:plyometric]},
    {~r/\brun|sprint|\bjog/u, [:running]},
    {~r/carry|farmer|\byoke\b/u, [:carry, :grip]},
    {~r/sit ?ups?\b|crunch|\bv ?ups?\b|hollow/u, [:core_flexion]},
    {~r/back extension|hip extension|superman|arch hold/u, [:spinal_extension]},
    {~r/tricep|skull/u, [:elbow_extension]},
    {~r/calf|calves/u, [:calf]},
    {~r/bike|cycl|assault|echo/u, [:cycling]},
    {~r/\bski/u, [:ski_erg]},
    {~r/swim/u, [:swimming]},
    {~r/plank/u, [:core_isometric]},
    {~r/hip thrust|bridge/u, [:hip_extension]},
    {~r/sled|prowler/u, [:sled]}
  ]

  @mobility_name ~r/stretch|mobility|foam roll/u
  @specific_row ~r/(barbell|dumbbell|\bdb|\bkb|kettlebell|ring|cable|seated|bent ?over|pendlay|upright|renegade|inverted)\s+rows?\b/u
  @erg_row ~r/\brow(s|er|ing)?\b/u

  # Canonical regions: accent-free, lower-case synonyms matched at the start
  # of a word (so plurals and inflections match), then the patterns that load
  # the region directly (primary) or indirectly (secondary).
  @regions [
    {:shoulder, ["shoulder", "rotator cuff", "labrum", "ac joint", "deltoid", "ωμο", "ωμοι"],
     [:overhead, :inversion, :dip, :hanging, :horizontal_push, :shoulder_mobility],
     [
       :vertical_pull,
       :horizontal_pull,
       :carry,
       :swimming,
       :rowing_erg,
       :ski_erg,
       :olympic,
       :shoulder_isolation
     ]},
    {:elbow, ["elbow", "tennis elbow", "golfer", "αγκων"],
     [:elbow_flexion, :elbow_extension, :dip],
     [
       :hanging,
       :vertical_pull,
       :horizontal_push,
       :horizontal_pull,
       :overhead,
       :inversion,
       :olympic,
       :grip
     ]},
    {:wrist,
     [
       "wrist",
       "hand",
       "finger",
       "thumb",
       "forearm",
       "carpal",
       "καρπ",
       "χερι",
       "δαχτυλ",
       "δακτυλ"
     ], [:wrist_extension, :inversion, :grip],
     [:horizontal_push, :olympic, :hanging, :overhead, :carry, :dip]},
    {:neck, ["neck", "cervical", "αυχεν"], [:inversion],
     [:overhead, :carry, :core_flexion, :olympic, :spinal_load]},
    {:back,
     [
       "back",
       "lumbar",
       "spine",
       "spinal",
       "sciatic",
       "sacroiliac",
       "si joint",
       "thoracic",
       "trap",
       "μεση",
       "πλατη",
       "οσφυ",
       "σπονδυλ",
       "μεσης"
     ], [:hinge, :spinal_load, :spinal_extension, :olympic, :spine_mobility],
     [
       :squat,
       :carry,
       :rowing_erg,
       :ski_erg,
       :core_flexion,
       :horizontal_pull,
       :plyometric,
       :rotation,
       :running,
       :sled,
       :hip_extension
     ]},
    {:hip, ["hip", "groin", "glute", "adductor", "pelvi", "ισχι", "γοφ", "βουβων", "γλουτ"],
     [:squat, :lunge, :hinge, :hip_extension, :hip_mobility],
     [:running, :plyometric, :olympic, :core_flexion, :cycling, :rowing_erg, :stair_climb, :sled]},
    {:knee,
     [
       "knee",
       "patell",
       "acl",
       "mcl",
       "pcl",
       "lcl",
       "menisc",
       "quad",
       "γονατ",
       "επιγονατ",
       "μηνισκ"
     ], [:squat, :lunge, :plyometric, :knee_mobility],
     [:running, :olympic, :cycling, :rowing_erg, :stair_climb, :sled]},
    {:hamstring, ["hamstring", "οπισθιο"],
     [:hinge, :running, :hamstring_curl, :hamstring_mobility],
     [:lunge, :olympic, :plyometric, :squat, :hip_extension]},
    {:ankle,
     [
       "ankle",
       "foot",
       "feet",
       "achilles",
       "heel",
       "toe",
       "calf",
       "calves",
       "shin",
       "plantar",
       "αστραγαλ",
       "ποδι",
       "φτερν",
       "γαμπ"
     ], [:plyometric, :running, :calf, :ankle_mobility],
     [:squat, :lunge, :olympic, :carry, :stair_climb, :sled]},
    {:chest, ["chest", "pec", "sternum", "rib", "στηθ", "θωρακ"], [:horizontal_push, :dip],
     [:overhead, :inversion, :hanging, :swimming]},
    {:core, ["abdom", "abs", "core", "hernia", "oblique", "κοιλι"], [:core_flexion, :rotation],
     [:hinge, :olympic, :hanging, :carry, :core_isometric, :spinal_load]}
  ]

  # Movement-restriction tags (after stripping a `no-` / `avoid-` prefix).
  @restriction_tags %{
    "overhead" => [:overhead, :inversion],
    "impact" => [:plyometric, :running],
    "high-impact" => [:plyometric, :running],
    "jumping" => [:plyometric],
    "jump" => [:plyometric],
    "plyometric" => [:plyometric],
    "plyometrics" => [:plyometric],
    "running" => [:running],
    "run" => [:running],
    "hanging" => [:hanging],
    "hang" => [:hanging],
    "spinal-loading" => [:spinal_load, :olympic],
    "axial-loading" => [:spinal_load, :olympic],
    "heavy-lifting" => [:spinal_load, :olympic],
    "inversion" => [:inversion],
    "inverted" => [:inversion],
    "grip" => [:grip, :hanging],
    "squat" => [:squat],
    "squatting" => [:squat],
    "deep-flexion" => [:squat],
    "lunge" => [:lunge],
    "lunging" => [:lunge],
    "pushing" => [:horizontal_push, :dip],
    "pulling" => [:vertical_pull, :horizontal_pull],
    "twisting" => [:rotation],
    "rotation" => [:rotation]
  }

  @doc "The curated catalog-id -> movement-pattern table (for coverage tests and docs)."
  def catalog_patterns, do: @catalog_patterns

  @doc "Every warning level, least to most severe."
  def levels, do: @levels

  @doc """
  Evaluates `injuries` against workout `exercises`.

  Returns `%{level: level, warnings: [warning]}` where each warning is
  `%{injury_id, user_id, body_area, regions, severity, level, provenance,
  training_limitations, tags, exercises: [%{name, exercise_ref, level,
  patterns, match}]}`. Only active injuries are considered; an injury with no
  affected exercise (and a recognised body area) produces no warning.
  """
  def evaluate(injuries, exercises) when is_list(injuries) and is_list(exercises) do
    descriptors = exercise_descriptors(exercises)

    warnings =
      injuries
      |> Enum.filter(&active?/1)
      |> Enum.flat_map(&injury_warning(&1, descriptors))

    %{level: max_level(Enum.map(warnings, & &1.level)), warnings: warnings}
  end

  @doc "Movement patterns for one exercise descriptor and how they were found."
  def exercise_patterns(exercise) do
    ref = field(exercise, :exercise_ref)

    case ref && Map.fetch(@catalog_patterns, ref) do
      {:ok, patterns} -> {patterns, :catalog}
      _no_catalog_match -> name_patterns(field(exercise, :name))
    end
  end

  @doc "Canonical body regions named by a free-text body area (in declaration order)."
  def regions_for(body_area) when is_binary(body_area) do
    haystack = " " <> normalize(body_area) <> " "

    @regions
    |> Enum.filter(fn {_region, synonyms, _primary, _secondary} ->
      Enum.any?(synonyms, &String.contains?(haystack, " " <> &1))
    end)
    |> Enum.map(&elem(&1, 0))
  end

  def regions_for(_body_area), do: []

  @doc "The most severe of `levels` (`:none` for an empty list)."
  def max_level(levels) do
    Enum.max_by([:none | levels], &Enum.find_index(@levels, fn level -> level == &1 end))
  end

  @doc """
  PII-free analytics summary of an evaluation: an enum and counts only. The
  free-text body area and limitations never leave this module through here.
  """
  def analytics_facts(%{level: level, warnings: warnings}) do
    exercise_levels =
      Enum.flat_map(warnings, fn warning -> Enum.map(warning.exercises, & &1.level) end)

    %{
      warning_level: Atom.to_string(level),
      injury_warning_count: length(warnings),
      avoid_exercise_count: Enum.count(exercise_levels, &(&1 == :avoid)),
      caution_exercise_count: Enum.count(exercise_levels, &(&1 == :caution))
    }
  end

  defp injury_warning(injury, descriptors) do
    severity = field(injury, :severity) || "moderate"
    tags = List.wrap(field(injury, :tags))
    regions = Enum.uniq(regions_for(field(injury, :body_area)) ++ tag_regions(tags))
    restricted = restricted_patterns(tags)

    exercises =
      descriptors
      |> Enum.map(&exercise_warning(&1, regions, restricted, severity))
      |> Enum.reject(&(&1.level == :none))

    cond do
      exercises != [] ->
        [
          build_warning(
            injury,
            regions,
            tags,
            max_level(Enum.map(exercises, & &1.level)),
            exercises
          )
        ]

      regions == [] and restricted == [] ->
        [build_warning(injury, regions, tags, :caution, [])]

      true ->
        []
    end
  end

  defp build_warning(injury, regions, tags, level, exercises) do
    %{
      injury_id: field(injury, :id),
      user_id: field(injury, :user_id),
      body_area: field(injury, :body_area),
      regions: regions,
      severity: field(injury, :severity),
      level: level,
      provenance: if(field(injury, :organization_id), do: :organization, else: :personal),
      training_limitations: field(injury, :training_limitations),
      tags: tags,
      exercises: exercises
    }
  end

  defp exercise_warning(%{patterns: patterns} = descriptor, regions, restricted, severity) do
    region_level =
      regions
      |> Enum.map(&region_level(&1, patterns, severity))
      |> max_level()

    tag_level = if Enum.any?(patterns, &(&1 in restricted)), do: :avoid, else: :none
    level = max_level([region_level, tag_level])
    level = if descriptor.mobility? and level == :avoid, do: :caution, else: level

    %{
      name: descriptor.name,
      exercise_ref: descriptor.exercise_ref,
      level: level,
      patterns: patterns,
      match: descriptor.match
    }
  end

  defp region_level(region, patterns, severity) do
    {_region, _synonyms, primary, secondary} = List.keyfind(@regions, region, 0)

    cond do
      Enum.any?(patterns, &(&1 in primary)) -> primary_level(severity)
      Enum.any?(patterns, &(&1 in secondary)) -> secondary_level(severity)
      true -> :none
    end
  end

  defp primary_level("mild"), do: :caution
  defp primary_level(_moderate_or_severe), do: :avoid

  defp secondary_level("mild"), do: :none
  defp secondary_level("severe"), do: :avoid
  defp secondary_level(_moderate), do: :caution

  defp exercise_descriptors(exercises) do
    exercises
    |> Enum.reject(&(to_string(field(&1, :item_type) || "exercise") == "header"))
    |> Enum.filter(&is_binary(field(&1, :name)))
    |> Enum.uniq_by(fn exercise ->
      field(exercise, :exercise_ref) || normalize(field(exercise, :name))
    end)
    |> Enum.map(fn exercise ->
      {patterns, match} = exercise_patterns(exercise)

      %{
        name: field(exercise, :name),
        exercise_ref: field(exercise, :exercise_ref),
        patterns: patterns,
        match: match,
        mobility?: mobility?(exercise, patterns)
      }
    end)
  end

  defp mobility?(exercise, patterns) do
    to_string(field(exercise, :category)) == "mobility" or
      (patterns != [] and Enum.all?(patterns, &(&1 in @mobility_patterns))) or
      Regex.match?(@mobility_name, normalize(field(exercise, :name) || ""))
  end

  defp name_patterns(name) when is_binary(name) do
    normalized = normalize(name)

    patterns =
      if Regex.match?(~r/leg curl|hamstring curl|nordic/u, normalized) do
        [:hamstring_curl]
      else
        @name_rules
        |> Enum.flat_map(fn {regex, patterns} ->
          if Regex.match?(regex, normalized), do: patterns, else: []
        end)
        |> Kernel.++(curl_patterns(normalized))
        |> Kernel.++(row_patterns(normalized))
        |> Enum.uniq()
      end

    case patterns do
      [] -> {[], :unmatched}
      patterns -> {patterns, :name}
    end
  end

  defp name_patterns(_name), do: {[], :unmatched}

  defp curl_patterns(name), do: if(Regex.match?(~r/curl/u, name), do: [:elbow_flexion], else: [])

  defp row_patterns(name) do
    cond do
      Regex.match?(@specific_row, name) -> [:horizontal_pull]
      Regex.match?(@erg_row, name) -> [:rowing_erg]
      true -> []
    end
  end

  defp tag_regions(tags), do: Enum.flat_map(tags, &regions_for/1)

  defp restricted_patterns(tags) do
    tags
    |> Enum.flat_map(fn tag -> Map.get(@restriction_tags, normalize_tag(tag), []) end)
    |> Enum.uniq()
  end

  defp normalize_tag(tag) when is_binary(tag) do
    tag
    |> normalize()
    |> String.replace(" ", "-")
    |> String.replace(~r/^(no|avoid)-/u, "")
  end

  defp normalize_tag(_tag), do: ""

  defp active?(injury), do: to_string(field(injury, :status) || "active") == "active"

  defp normalize(value) when is_binary(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  defp normalize(_value), do: ""

  defp field(map, key) when is_map(map) do
    case Map.get(map, key) do
      nil -> Map.get(map, Atom.to_string(key))
      value -> value
    end
  end

  defp field(_map, _key), do: nil
end
