defmodule Palee.Anatomy do
  @moduledoc """
  Public API of the code-owned anatomy vocabulary (ADR-163): the versioned
  muscle taxonomy, the ten fitness qualities, deterministic goal suggestion
  and goal/feedback validation. Pure; no persistence.
  """

  alias Palee.Anatomy.Domain.{
    Coverage,
    CoverageBalance,
    CoverageWeighting,
    ExerciseTargets,
    FeedbackSummary,
    FitnessQualities,
    GoalSet,
    GoalSuggestion,
    MuscleTaxonomy,
    NodeExercises,
    QualityProfile
  }

  def taxonomy_version, do: MuscleTaxonomy.version()

  @doc """
  The whole taxonomy for clients: version, every node in tree order
  (`id, kind, parent_id, name, ta2_ids`), the qualities and the goal roles.
  """
  def taxonomy do
    %{
      version: MuscleTaxonomy.version(),
      nodes:
        Enum.map(MuscleTaxonomy.nodes(), fn node ->
          %{
            id: node.id,
            kind: Atom.to_string(node.kind),
            parent_id: node.parent_id,
            name: node.name,
            ta2_ids: node.ta2_ids
          }
        end),
      qualities: FitnessQualities.all(),
      roles: Enum.map(ExerciseTargets.roles(), &Atom.to_string/1)
    }
  end

  @doc "Suggested goals from `[%{exercise_ref, weight}]` (deterministic, ADR-163 D3)."
  def suggest_goals(exercises), do: GoalSuggestion.suggest(exercises)

  @doc """
  Coach totals of goal feedback (ADR-163): counts per muscle group and
  quality and the goal groups nobody felt, only from three entries up.
  """
  def summarize_feedback(rows, goal_muscles), do: FeedbackSummary.summarize(rows, goal_muscles)

  def normalize_goals(params), do: GoalSet.normalize_goals(params)
  def normalize_feedback(params), do: GoalSet.normalize_feedback(params)

  # -- Anatomy atlas and coverage (ADR-164) ------------------------------------

  @doc "`{:ok, range, weeks}` for an atlas range (`1w`, `4w`, `12w`; nil = 4w)."
  def parse_coverage_range(range), do: CoverageWeighting.parse_range(range)

  def coverage_ranges, do: CoverageWeighting.ranges()
  def coverage_thresholds, do: CoverageWeighting.thresholds()
  def coverage_levels, do: CoverageWeighting.levels()

  @doc """
  Muscle coverage of performed workouts: weighted sets, per-week level,
  felt count and top exercises per node (`CoverageWeighting` policy).
  """
  def coverage(performances, felt, weeks), do: Coverage.build(performances, felt, weeks)

  @doc "Catalog exercises that train a node, strongest role first; `:error` when unknown."
  def exercises_for_node(node_id), do: NodeExercises.for_node(node_id)

  def known_node?(node_id), do: MuscleTaxonomy.known?(node_id)

  # -- Πρόοδος: coverage summary and qualities radar (ADR-165) -----------------

  @doc """
  Most and least trained major groups and the push:pull and quad:ham
  ratios, from coverage nodes and the performances behind them.
  """
  def coverage_summary(nodes, performances), do: CoverageBalance.summarize(nodes, performances)

  @doc "Sets and felt entries per fitness quality, with a 0..1 radar score."
  def quality_profile(performances, felt), do: QualityProfile.build(performances, felt)
end
