defmodule MilosTraining.Anatomy.Domain.CoverageBalance do
  @moduledoc """
  The Πρόοδος summary of muscle coverage (ADR-165): which major muscle
  groups were trained the most and the least, and two balance ratios, push
  to pull and quadriceps to hamstrings. Pure; it reads the nodes that
  `Coverage.build/3` returns and the same performances.

  ## Major groups
  The summary only names the large groups an athlete recognises (the
  `@major_groups` list); small and deep muscles stay in the atlas. "Least"
  lists major groups at level `none` or `low`, lowest first; "most" the
  groups with the most weighted sets.

  ## Balance
  Balance counts **exercise sets**, not muscle sets: a set is push when the
  exercise's primary muscles include a pushing muscle, pull when they include
  a pulling one, half of each when both (a muscle-up). Quadriceps and
  hamstrings work the same way with quad- and hamstring-dominant exercises.
  A ratio is given only once both sides have sets and together reach
  `@ratio_min_sets`; it is an indication, never a target.
  """

  alias MilosTraining.Anatomy.Domain.{ExerciseTargets, MuscleTaxonomy}

  @major_groups [
    "deltoid",
    "pectoralis-major",
    "latissimus-dorsi",
    "trapezius",
    "erector-spinae",
    "biceps-brachii",
    "triceps-brachii",
    "rectus-abdominis",
    "obliques",
    "glutes",
    "quadriceps",
    "hamstrings",
    "adductors",
    "calves"
  ]

  @listed 3
  @ratio_min_sets 4

  @push_groups ["pectoralis-major", "triceps-brachii"]
  @push_heads ["deltoid", "deltoid-anterior", "deltoid-lateral"]
  @pull_groups ["latissimus-dorsi", "rhomboids", "biceps-brachii", "brachialis", "teres-major"]
  @pull_heads ["trapezius-middle", "trapezius-lower", "deltoid-posterior"]

  expand = fn groups -> Enum.flat_map(groups, &[&1 | MuscleTaxonomy.heads_of(&1)]) end

  @push MapSet.new(expand.(@push_groups) ++ @push_heads)
  @pull MapSet.new(expand.(@pull_groups) ++ @pull_heads)
  @quad MapSet.new(expand.(["quadriceps"]))
  @ham MapSet.new(expand.(["hamstrings"]))

  def major_groups, do: @major_groups
  def ratio_min_sets, do: @ratio_min_sets

  @doc """
  `%{most: [node], least: [node], balance: %{push, pull, push_pull_ratio,
  quad, ham, quad_ham_ratio}}` from the coverage nodes and the performances
  they were built from. Each listed node is `%{id, sets, per_week, level}`.
  """
  def summarize(nodes, performances) when is_list(nodes) and is_list(performances) do
    by_id = Map.new(nodes, &{&1.id, &1})

    majors =
      Enum.map(@major_groups, fn id ->
        node = Map.get(by_id, id, %{sets: 0.0, per_week: 0.0, level: "none"})
        %{id: id, sets: node.sets, per_week: node.per_week, level: node.level}
      end)

    exercises = Enum.flat_map(performances, &List.wrap(Map.get(&1, :exercises)))

    %{
      most:
        majors
        |> Enum.filter(&(&1.sets > 0))
        |> Enum.sort_by(&(-&1.sets))
        |> Enum.take(@listed),
      least:
        if exercises == [] do
          []
        else
          majors
          |> Enum.filter(&(&1.level in ["none", "low"]))
          |> Enum.sort_by(& &1.per_week)
          |> Enum.take(@listed)
        end,
      balance: balance(exercises)
    }
  end

  defp balance(exercises) do
    {push, pull, quad, ham} =
      Enum.reduce(exercises, {0.0, 0.0, 0.0, 0.0}, fn exercise, {push, pull, quad, ham} ->
        primary = primary_muscles(Map.get(exercise, :exercise_ref))
        sets = sets(exercise)
        {p, q} = split(primary, @push, @pull)
        {qd, hm} = split(primary, @quad, @ham)
        {push + p * sets, pull + q * sets, quad + qd * sets, ham + hm * sets}
      end)

    %{
      push: round1(push),
      pull: round1(pull),
      push_pull_ratio: ratio(push, pull),
      quad: round1(quad),
      ham: round1(ham),
      quad_ham_ratio: ratio(quad, ham)
    }
  end

  defp primary_muscles(ref) do
    case ExerciseTargets.fetch(ref) do
      %{muscles: muscles} -> for %{id: id, role: :primary} <- muscles, do: id
      nil -> []
    end
  end

  # How much of one set goes to each side: 1/0, 0/1, ½/½ or nothing.
  defp split(primary, left, right) do
    case {Enum.any?(primary, &MapSet.member?(left, &1)),
          Enum.any?(primary, &MapSet.member?(right, &1))} do
      {true, true} -> {0.5, 0.5}
      {true, false} -> {1.0, 0.0}
      {false, true} -> {0.0, 1.0}
      {false, false} -> {0.0, 0.0}
    end
  end

  defp ratio(a, b) when a > 0 and b > 0 and a + b >= @ratio_min_sets, do: Float.round(a / b, 2)
  defp ratio(_a, _b), do: nil

  defp sets(%{sets: sets}) when is_integer(sets) and sets > 0, do: sets
  defp sets(_exercise), do: 1

  defp round1(value), do: Float.round(value * 1.0, 1)
end
