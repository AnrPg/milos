defmodule MilosTraining.Anatomy do
  @moduledoc """
  Public API of the code-owned anatomy vocabulary (ADR-163): the versioned
  muscle taxonomy, the ten fitness qualities, deterministic goal suggestion
  and goal/feedback validation. Pure; no persistence.
  """

  alias MilosTraining.Anatomy.Domain.{
    ExerciseTargets,
    FeedbackSummary,
    FitnessQualities,
    GoalSet,
    GoalSuggestion,
    MuscleTaxonomy
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
end
