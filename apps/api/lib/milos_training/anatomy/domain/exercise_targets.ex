defmodule MilosTraining.Anatomy.Domain.ExerciseTargets do
  @moduledoc """
  Curated, code-owned map from a Quick Text catalog id
  (`Workouts.Domain.WorkoutDsl.ExerciseCatalog`) to the muscles it trains and
  the fitness qualities it develops (ADR-163).

  Keyed by the same stable ids as the injury-risk policy (ADR-124), so WOD
  goals, coverage and injury warnings reason about one exercise vocabulary. A
  coverage test fails when the catalog gains an id without an entry here.

  Roles:

    * `:primary` - the movement's prime movers
    * `:secondary` - synergists that do meaningful work
    * `:stabilizer` - muscles that hold position under load

  Targets name groups or heads of `MuscleTaxonomy`; a group means "the whole
  group" and rolls up the same way in coverage.
  """

  alias MilosTraining.Anatomy.Domain.{FitnessQualities, MuscleTaxonomy}

  @qualities %{
    end: "cardiorespiratory-endurance",
    sta: "stamina",
    str: "strength",
    flex: "flexibility",
    pow: "power",
    spd: "speed",
    coord: "coordination",
    agi: "agility",
    bal: "balance",
    acc: "accuracy"
  }

  # Shared muscle sets, so similar movements stay consistent.
  @squat_core ["rectus-abdominis", "obliques", "erector-spinae"]
  @brace ["rectus-abdominis", "obliques", "transversus-abdominis"]
  @hinge_back ["erector-spinae", "multifidus"]
  @grip ["forearm-flexors"]
  @overhead_stab ["trapezius-upper", "serratus-anterior", "rotator-cuff"] ++ @brace

  # id => {primary, secondary, stabilizer, qualities}
  @targets %{
    "air-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductor-magnus"], @squat_core, [:sta, :flex]},
    "back-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductor-magnus", "hamstrings"], @squat_core, [:str]},
    "front-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductor-magnus"],
       @squat_core ++ ["trapezius-upper", "rhomboids"], [:str]},
    "overhead-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductor-magnus", "deltoid"],
       @squat_core ++ ["trapezius", "rotator-cuff", "serratus-anterior"],
       [:str, :flex, :bal, :coord]},
    "goblet-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductor-magnus"], @squat_core ++ ["biceps-brachii"],
       [:str, :flex]},
    "box-squat" =>
      {["gluteus-maximus", "quadriceps"], ["hamstrings", "adductor-magnus"], @squat_core,
       [:str, :pow]},
    "split-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductors"], ["gluteus-medius" | @brace],
       [:str, :bal]},
    "bulgarian-split-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductors", "hamstrings"],
       ["gluteus-medius" | @brace], [:str, :bal]},
    "pistol-squat" =>
      {["quadriceps", "gluteus-maximus"], ["adductors", "calves"],
       ["gluteus-medius", "tibialis-anterior" | @brace], [:str, :bal, :flex, :coord]},
    "wall-sit" => {["quadriceps"], ["gluteus-maximus"], @brace, [:sta]},
    "deadlift" =>
      {["gluteus-maximus", "hamstrings", "erector-spinae"], ["quadriceps", "adductor-magnus"],
       @grip ++ ["trapezius", "latissimus-dorsi" | @brace], [:str]},
    "sumo-deadlift" =>
      {["gluteus-maximus", "adductors", "quadriceps"], ["hamstrings", "erector-spinae"],
       @grip ++ ["trapezius", "latissimus-dorsi" | @brace], [:str]},
    "romanian-deadlift" =>
      {["hamstrings", "gluteus-maximus"], ["erector-spinae", "adductor-magnus"],
       @grip ++ ["latissimus-dorsi", "trapezius-middle" | @brace], [:str, :flex]},
    "stiff-leg-deadlift" =>
      {["hamstrings", "gluteus-maximus"], ["erector-spinae"],
       @grip ++ ["latissimus-dorsi" | @brace], [:str, :flex]},
    "single-leg-deadlift" =>
      {["hamstrings", "gluteus-maximus"], ["erector-spinae"],
       ["gluteus-medius", "calves" | @brace], [:str, :bal]},
    "clean" =>
      {["gluteus-maximus", "hamstrings", "quadriceps"],
       ["trapezius-upper", "erector-spinae", "calves"], ["deltoid", "rhomboids" | @brace],
       [:pow, :str, :spd, :coord]},
    "power-clean" =>
      {["gluteus-maximus", "hamstrings", "trapezius-upper"],
       ["quadriceps", "erector-spinae", "calves"], ["deltoid", "rhomboids" | @brace],
       [:pow, :spd, :coord]},
    "hang-clean" =>
      {["gluteus-maximus", "hamstrings", "trapezius-upper"], ["quadriceps", "erector-spinae"],
       ["deltoid", "rhomboids" | @brace], [:pow, :spd, :coord]},
    "clean-and-jerk" =>
      {["gluteus-maximus", "quadriceps", "hamstrings", "deltoid-anterior"],
       ["triceps-brachii", "trapezius-upper", "erector-spinae", "calves"], @overhead_stab,
       [:pow, :str, :spd, :coord, :bal]},
    "snatch" =>
      {["gluteus-maximus", "hamstrings", "quadriceps", "trapezius-upper"],
       ["deltoid", "erector-spinae", "calves"], @overhead_stab,
       [:pow, :spd, :coord, :flex, :bal, :acc]},
    "power-snatch" =>
      {["gluteus-maximus", "hamstrings", "trapezius-upper"],
       ["deltoid", "quadriceps", "erector-spinae"], @overhead_stab, [:pow, :spd, :coord, :acc]},
    "hang-snatch" =>
      {["gluteus-maximus", "hamstrings", "trapezius-upper"], ["deltoid", "quadriceps"],
       @overhead_stab, [:pow, :spd, :coord, :acc]},
    "muscle-snatch" =>
      {["trapezius-upper", "deltoid"], ["gluteus-maximus", "hamstrings", "rotator-cuff"],
       @overhead_stab, [:pow, :coord, :flex]},
    "jerk" =>
      {["quadriceps", "gluteus-maximus", "deltoid-anterior", "triceps-brachii"], ["calves"],
       @overhead_stab, [:pow, :spd, :coord, :bal]},
    "push-jerk" =>
      {["quadriceps", "deltoid-anterior", "triceps-brachii"], ["gluteus-maximus", "calves"],
       @overhead_stab, [:pow, :spd, :coord]},
    "push-press" =>
      {["deltoid-anterior", "triceps-brachii", "quadriceps"],
       ["deltoid-lateral", "gluteus-maximus"], @overhead_stab, [:pow, :str]},
    "strict-press" =>
      {["deltoid-anterior", "triceps-brachii"],
       ["deltoid-lateral", "pectoralis-major-clavicular"], @overhead_stab ++ ["gluteus-maximus"],
       [:str]},
    "bench-press" =>
      {["pectoralis-major", "triceps-brachii"], ["deltoid-anterior"],
       ["latissimus-dorsi", "rotator-cuff", "rhomboids"], [:str]},
    "incline-bench-press" =>
      {["pectoralis-major-clavicular", "deltoid-anterior", "triceps-brachii"],
       ["pectoralis-major-sternocostal"], ["rotator-cuff", "rhomboids"], [:str]},
    "floor-press" =>
      {["triceps-brachii", "pectoralis-major"], ["deltoid-anterior"], ["rotator-cuff"], [:str]},
    "dumbbell-bench-press" =>
      {["pectoralis-major", "triceps-brachii"], ["deltoid-anterior"],
       ["rotator-cuff", "serratus-anterior"], [:str, :bal]},
    "dumbbell-row" =>
      {["latissimus-dorsi", "rhomboids", "trapezius-middle"],
       ["deltoid-posterior", "biceps-brachii", "brachialis"],
       @grip ++ ["obliques", "erector-spinae"], [:str]},
    "barbell-row" =>
      {["latissimus-dorsi", "rhomboids", "trapezius-middle"],
       ["deltoid-posterior", "biceps-brachii", "teres-major"],
       @grip ++ @hinge_back ++ ["hamstrings"], [:str]},
    "pendlay-row" =>
      {["latissimus-dorsi", "rhomboids", "trapezius-middle"],
       ["deltoid-posterior", "biceps-brachii"], @grip ++ @hinge_back ++ ["hamstrings"],
       [:str, :pow]},
    "upright-row" =>
      {["trapezius-upper", "deltoid-lateral"], ["deltoid-anterior", "biceps-brachii"], @grip,
       [:str]},
    "good-morning" =>
      {["hamstrings", "erector-spinae"], ["gluteus-maximus", "adductor-magnus"], @brace,
       [:str, :flex]},
    "hip-thrust" => {["gluteus-maximus"], ["hamstrings", "quadriceps"], @brace, [:str]},
    "glute-bridge" => {["gluteus-maximus"], ["hamstrings"], ["rectus-abdominis"], [:sta]},
    "lunge" =>
      {["quadriceps", "gluteus-maximus"], ["adductors", "hamstrings"],
       ["gluteus-medius" | @brace], [:str, :bal, :coord]},
    "reverse-lunge" =>
      {["gluteus-maximus", "quadriceps"], ["hamstrings", "adductors"],
       ["gluteus-medius" | @brace], [:str, :bal]},
    "walking-lunge" =>
      {["quadriceps", "gluteus-maximus"], ["adductors", "hamstrings", "calves"],
       ["gluteus-medius" | @brace], [:sta, :bal, :coord]},
    "step-up" =>
      {["quadriceps", "gluteus-maximus"], ["hamstrings", "calves"], ["gluteus-medius" | @brace],
       [:str, :bal]},
    "calf-raise" => {["calves"], [], ["tibialis-anterior"], [:str, :bal]},
    "biceps-curl" => {["biceps-brachii"], ["brachialis", "brachioradialis"], @grip, [:str]},
    "triceps-extension" => {["triceps-brachii"], [], ["rotator-cuff"], [:str]},
    "skull-crusher" => {["triceps-brachii"], [], ["rotator-cuff"], [:str]},
    "lateral-raise" => {["deltoid-lateral"], ["trapezius-upper", "supraspinatus"], [], [:str]},
    "front-raise" => {["deltoid-anterior"], ["pectoralis-major-clavicular"], @brace, [:str]},
    "face-pull" =>
      {["deltoid-posterior", "trapezius-middle"], ["infraspinatus", "teres-minor", "rhomboids"],
       [], [:str, :coord]},
    "farmer-carry" =>
      {["forearm-flexors", "trapezius-upper"], ["obliques", "gluteus-medius"],
       ["quadratus-lumborum", "erector-spinae", "calves"], [:str, :sta]},
    "front-rack-carry" =>
      {["rectus-abdominis", "trapezius-upper"], ["deltoid-anterior", "biceps-brachii"],
       ["erector-spinae", "obliques", "quadriceps"], [:str, :sta]},
    "overhead-carry" =>
      {["deltoid", "triceps-brachii"], ["trapezius-upper", "serratus-anterior"],
       ["rotator-cuff" | @brace], [:str, :sta, :bal]},
    "sled-push" =>
      {["quadriceps", "gluteus-maximus"], ["calves", "hamstrings"],
       ["triceps-brachii", "deltoid-anterior" | @brace], [:str, :pow, :sta]},
    "sled-pull" =>
      {["hamstrings", "gluteus-maximus"], ["quadriceps", "calves", "latissimus-dorsi"],
       @grip ++ @brace, [:str, :sta]},
    "kettlebell-swing" =>
      {["gluteus-maximus", "hamstrings"], ["erector-spinae", "deltoid-anterior"],
       @grip ++ ["latissimus-dorsi" | @brace], [:pow, :sta, :end]},
    "american-kettlebell-swing" =>
      {["gluteus-maximus", "hamstrings"], ["erector-spinae", "deltoid", "trapezius-upper"],
       @grip ++ ["latissimus-dorsi", "serratus-anterior" | @brace], [:pow, :sta, :end, :flex]},
    "russian-kettlebell-swing" =>
      {["gluteus-maximus", "hamstrings"], ["erector-spinae"],
       @grip ++ ["latissimus-dorsi" | @brace], [:pow, :sta]},
    "turkish-get-up" =>
      {["deltoid", "obliques", "gluteus-maximus"], ["triceps-brachii", "quadriceps"],
       ["rotator-cuff", "serratus-anterior", "trapezius" | @brace], [:str, :bal, :coord, :flex]},
    "thruster" =>
      {["quadriceps", "gluteus-maximus", "deltoid-anterior"],
       ["triceps-brachii", "deltoid-lateral"], @overhead_stab, [:sta, :pow, :end, :coord]},
    "wall-ball" =>
      {["quadriceps", "gluteus-maximus", "deltoid-anterior"], ["triceps-brachii"], @overhead_stab,
       [:sta, :end, :coord, :acc]},
    "devil-press" =>
      {["gluteus-maximus", "hamstrings", "pectoralis-major", "deltoid"],
       ["triceps-brachii", "quadriceps"], @overhead_stab, [:sta, :pow, :end, :coord]},
    "man-maker" =>
      {["pectoralis-major", "latissimus-dorsi", "quadriceps", "deltoid"],
       ["triceps-brachii", "gluteus-maximus", "rhomboids"], @overhead_stab, [:sta, :str, :coord]},
    "push-up" =>
      {["pectoralis-major", "triceps-brachii"], ["deltoid-anterior"],
       ["serratus-anterior" | @brace], [:str, :sta]},
    "hand-release-push-up" =>
      {["pectoralis-major", "triceps-brachii"], ["deltoid-anterior", "rhomboids"],
       ["serratus-anterior" | @brace], [:sta, :str]},
    "diamond-push-up" =>
      {["triceps-brachii", "pectoralis-major"], ["deltoid-anterior"],
       ["serratus-anterior" | @brace], [:str]},
    "dip" =>
      {["triceps-brachii", "pectoralis-major-sternocostal"], ["deltoid-anterior"],
       ["pectoralis-minor", "rhomboids"], [:str]},
    "ring-dip" =>
      {["triceps-brachii", "pectoralis-major-sternocostal"], ["deltoid-anterior"],
       ["rotator-cuff", "pectoralis-minor", "biceps-brachii" | @brace], [:str, :bal, :coord]},
    "pull-up" =>
      {["latissimus-dorsi", "biceps-brachii"],
       ["teres-major", "rhomboids", "trapezius-lower", "brachialis"],
       @grip ++ ["rectus-abdominis"], [:str, :sta]},
    "strict-pull-up" =>
      {["latissimus-dorsi", "biceps-brachii"],
       ["teres-major", "rhomboids", "trapezius-lower", "brachialis"], @grip ++ @brace, [:str]},
    "chest-to-bar-pull-up" =>
      {["latissimus-dorsi", "rhomboids", "biceps-brachii"],
       ["trapezius-middle", "trapezius-lower", "teres-major"],
       @grip ++ ["rectus-abdominis", "hip-flexors"], [:str, :sta, :coord]},
    "chin-up" =>
      {["latissimus-dorsi", "biceps-brachii"], ["brachialis", "teres-major", "rhomboids"],
       @grip ++ ["rectus-abdominis"], [:str]},
    "ring-row" =>
      {["latissimus-dorsi", "rhomboids", "trapezius-middle"],
       ["biceps-brachii", "deltoid-posterior"], @grip ++ ["gluteus-maximus" | @brace],
       [:str, :sta]},
    "muscle-up" =>
      {["latissimus-dorsi", "triceps-brachii", "pectoralis-major"],
       ["biceps-brachii", "deltoid-anterior"], @grip ++ ["rotator-cuff", "hip-flexors" | @brace],
       [:str, :pow, :coord, :agi]},
    "ring-muscle-up" =>
      {["latissimus-dorsi", "triceps-brachii", "pectoralis-major"],
       ["biceps-brachii", "deltoid-anterior"], @grip ++ ["rotator-cuff", "hip-flexors" | @brace],
       [:str, :pow, :coord, :bal]},
    "bar-muscle-up" =>
      {["latissimus-dorsi", "triceps-brachii"],
       ["pectoralis-major", "biceps-brachii", "deltoid-anterior"],
       @grip ++ ["hip-flexors" | @brace], [:str, :pow, :coord, :agi]},
    "rope-climb" =>
      {["latissimus-dorsi", "biceps-brachii", "forearm-flexors"], ["brachialis", "rhomboids"],
       ["quadriceps", "adductors" | @brace], [:str, :coord]},
    "legless-rope-climb" =>
      {["latissimus-dorsi", "biceps-brachii", "forearm-flexors"],
       ["brachialis", "rhomboids", "teres-major"], @brace ++ ["hip-flexors"], [:str, :coord]},
    "toes-to-bar" =>
      {["rectus-abdominis", "hip-flexors"], ["obliques", "latissimus-dorsi"],
       @grip ++ ["serratus-anterior"], [:sta, :coord, :flex]},
    "knees-to-elbows" =>
      {["rectus-abdominis", "hip-flexors"], ["obliques", "latissimus-dorsi"], @grip,
       [:sta, :coord]},
    "sit-up" => {["rectus-abdominis", "hip-flexors"], ["obliques"], [], [:sta]},
    "ghd-sit-up" =>
      {["rectus-abdominis", "hip-flexors"], ["obliques", "quadriceps"], ["transversus-abdominis"],
       [:str, :sta]},
    "v-up" =>
      {["rectus-abdominis", "hip-flexors"], ["obliques"], ["transversus-abdominis"],
       [:sta, :coord]},
    "hollow-hold" =>
      {["rectus-abdominis", "transversus-abdominis"], ["hip-flexors", "obliques"], [], [:sta]},
    "arch-hold" =>
      {["erector-spinae", "gluteus-maximus"], ["hamstrings", "trapezius-lower"], ["multifidus"],
       [:sta]},
    "plank" =>
      {["rectus-abdominis", "transversus-abdominis"], ["obliques"],
       ["serratus-anterior", "gluteus-maximus", "deltoid-anterior"], [:sta]},
    "side-plank" =>
      {["obliques", "quadratus-lumborum"], ["gluteus-medius"],
       ["transversus-abdominis", "deltoid-lateral"], [:sta, :bal]},
    "pallof-press" =>
      {["obliques", "transversus-abdominis"], ["rectus-abdominis"],
       ["gluteus-medius", "deltoid-anterior"], [:str, :bal]},
    "back-extension" =>
      {["erector-spinae", "gluteus-maximus"], ["hamstrings"], ["multifidus"], [:str, :sta]},
    "burpee" =>
      {["pectoralis-major", "quadriceps", "gluteus-maximus"],
       ["triceps-brachii", "deltoid-anterior", "calves"], @brace ++ ["hip-flexors"],
       [:end, :sta, :agi, :coord]},
    "burpee-box-jump" =>
      {["quadriceps", "gluteus-maximus", "pectoralis-major"],
       ["calves", "triceps-brachii", "hamstrings"], @brace ++ ["hip-flexors"],
       [:end, :sta, :pow, :agi, :coord]},
    "box-jump" =>
      {["quadriceps", "gluteus-maximus", "calves"], ["hamstrings"], @brace, [:pow, :coord, :acc]},
    "box-jump-over" =>
      {["quadriceps", "gluteus-maximus", "calves"], ["hamstrings"], @brace,
       [:pow, :sta, :agi, :coord]},
    "broad-jump" =>
      {["gluteus-maximus", "quadriceps", "hamstrings"], ["calves"], @brace, [:pow, :coord, :bal]},
    "double-under" =>
      {["calves"], ["forearm-flexors", "deltoid"], ["quadriceps", "tibialis-anterior" | @brace],
       [:end, :coord, :acc, :spd]},
    "single-under" => {["calves"], ["forearm-flexors"], ["tibialis-anterior"], [:end, :coord]},
    "handstand-hold" =>
      {["deltoid", "triceps-brachii"], ["trapezius-upper", "serratus-anterior"],
       ["forearm-flexors", "rotator-cuff" | @brace], [:str, :bal]},
    "handstand-walk" =>
      {["deltoid", "triceps-brachii"], ["trapezius-upper", "serratus-anterior"],
       ["forearm-flexors", "rotator-cuff" | @brace], [:str, :bal, :coord, :acc]},
    "handstand-push-up" =>
      {["deltoid-anterior", "triceps-brachii"],
       ["trapezius-upper", "pectoralis-major-clavicular", "deltoid-lateral"],
       ["serratus-anterior", "rotator-cuff" | @brace], [:str, :bal]},
    "wall-walk" =>
      {["deltoid", "triceps-brachii"], ["pectoralis-major-clavicular", "trapezius-upper"],
       ["serratus-anterior" | @brace], [:str, :bal, :coord]},
    "run" =>
      {["quadriceps", "hamstrings", "calves"], ["gluteus-maximus", "hip-flexors"],
       ["gluteus-medius" | @brace], [:end, :sta]},
    "sprint" =>
      {["hamstrings", "gluteus-maximus", "quadriceps", "calves"], ["hip-flexors"],
       ["gluteus-medius" | @brace], [:spd, :pow, :agi]},
    "row" =>
      {["quadriceps", "latissimus-dorsi", "gluteus-maximus"],
       ["hamstrings", "rhomboids", "biceps-brachii", "erector-spinae"],
       @grip ++ ["rectus-abdominis"], [:end, :sta, :pow]},
    "bike" =>
      {["quadriceps", "gluteus-maximus"], ["hamstrings", "calves"], ["hip-flexors"], [:end, :sta]},
    "air-bike" =>
      {["quadriceps", "gluteus-maximus"],
       ["hamstrings", "deltoid", "triceps-brachii", "latissimus-dorsi"], @brace,
       [:end, :sta, :pow]},
    "ski-erg" =>
      {["latissimus-dorsi", "triceps-brachii"],
       ["rectus-abdominis", "gluteus-maximus", "hamstrings", "teres-major"],
       @grip ++ ["serratus-anterior"], [:end, :sta, :pow]},
    "swim" =>
      {["latissimus-dorsi", "deltoid"], ["triceps-brachii", "pectoralis-major", "quadriceps"],
       @brace ++ ["rotator-cuff"], [:end, :sta, :coord]},
    "stair-climb" =>
      {["quadriceps", "gluteus-maximus"], ["calves", "hamstrings"], ["gluteus-medius"],
       [:end, :sta]},
    "jumping-jack" =>
      {["calves", "deltoid-lateral"], ["gluteus-medius", "adductors"], [], [:end, :coord]},
    "mountain-climber" =>
      {["hip-flexors", "rectus-abdominis"], ["quadriceps", "deltoid-anterior"],
       ["serratus-anterior", "obliques"], [:end, :sta, :agi]},
    "bear-crawl" =>
      {["deltoid-anterior", "quadriceps"], ["triceps-brachii", "hip-flexors"],
       ["serratus-anterior" | @brace], [:sta, :coord, :agi]},
    "hip-flexor-stretch" => {["hip-flexors"], ["rectus-femoris"], [], [:flex]},
    "hamstring-stretch" => {["hamstrings"], ["calves"], [], [:flex]},
    "quad-stretch" => {["quadriceps"], ["hip-flexors"], [], [:flex]},
    "calf-stretch" => {["calves"], [], [], [:flex]},
    "pigeon-stretch" => {["gluteus-maximus", "hip-rotators"], ["hip-flexors"], [], [:flex]},
    "couch-stretch" => {["rectus-femoris", "hip-flexors"], ["quadriceps"], [], [:flex]},
    "child-pose" => {["latissimus-dorsi", "erector-spinae"], ["gluteus-maximus"], [], [:flex]},
    "downward-dog" => {["hamstrings", "calves"], ["latissimus-dorsi", "deltoid"], [], [:flex]},
    "cat-cow" => {["erector-spinae", "rectus-abdominis"], ["multifidus"], [], [:flex, :coord]},
    "thoracic-rotation" => {["obliques", "erector-spinae"], ["rhomboids"], [], [:flex]},
    "shoulder-dislocate" =>
      {["deltoid", "rotator-cuff"], ["pectoralis-major", "trapezius"], [], [:flex]},
    "band-pull-apart" =>
      {["deltoid-posterior", "rhomboids", "trapezius-middle"], ["infraspinatus", "teres-minor"],
       [], [:flex, :coord]},
    "foam-roll" => {[], [], [], [:flex]}
  }

  @role_rank %{primary: 3, secondary: 2, stabilizer: 1}

  @doc "Catalog ids with a curated decision (for the coverage test)."
  def ids, do: Map.keys(@targets)

  @doc """
  Targets of one catalog id: `%{muscles: [%{id, role}], qualities: [id]}`, or
  `nil` when the id is unknown. A muscle listed under several roles keeps the
  strongest one.
  """
  def fetch(catalog_id) when is_binary(catalog_id) do
    case Map.fetch(@targets, catalog_id) do
      {:ok, {primary, secondary, stabilizer, qualities}} ->
        %{
          muscles: merge_roles(primary: primary, secondary: secondary, stabilizer: stabilizer),
          qualities:
            qualities |> Enum.map(&Map.fetch!(@qualities, &1)) |> FitnessQualities.normalize()
        }

      :error ->
        nil
    end
  end

  def fetch(_catalog_id), do: nil

  @doc "Ordering weight of a role; higher is stronger."
  def role_rank(role), do: Map.fetch!(@role_rank, role)

  def roles, do: [:primary, :secondary, :stabilizer]

  defp merge_roles(lists) do
    lists
    |> Enum.flat_map(fn {role, ids} -> Enum.map(ids, &{&1, role}) end)
    |> Enum.reduce(%{}, fn {id, role}, acc ->
      Map.update(acc, id, role, &stronger(&1, role))
    end)
    |> Enum.map(fn {id, role} -> %{id: id, role: role} end)
    |> Enum.sort_by(fn %{id: id, role: role} -> {-role_rank(role), node_order(id)} end)
  end

  defp stronger(a, b), do: if(role_rank(a) >= role_rank(b), do: a, else: b)

  @node_order MuscleTaxonomy.nodes() |> Enum.with_index() |> Map.new(fn {n, i} -> {n.id, i} end)
  defp node_order(id), do: Map.get(@node_order, id, 10_000)
end
