defmodule Palee.Anatomy.Domain.NodeExercises do
  @moduledoc """
  The catalog exercises that train a taxonomy node (ADR-164): those whose
  primary or secondary targets reach it under the `CoverageWeighting` reach
  rule (a head target reaches its group and region, a group target its heads
  and region). Stabilizers do not count as training a muscle. Pure.
  """

  alias Palee.Anatomy.Domain.{CoverageWeighting, ExerciseTargets, MuscleTaxonomy}

  @doc """
  `[%{exercise_ref, role}]` for a known node id, strongest role first, then
  catalog id; `:error` for an unknown node.
  """
  def for_node(node_id) do
    if MuscleTaxonomy.known?(node_id) do
      {:ok,
       ExerciseTargets.ids()
       |> Enum.flat_map(&role_for(&1, node_id))
       |> Enum.sort_by(fn %{exercise_ref: ref, role: role} ->
         {-ExerciseTargets.role_rank(role), ref}
       end)}
    else
      :error
    end
  end

  defp role_for(catalog_id, node_id) do
    %{muscles: muscles} = ExerciseTargets.fetch(catalog_id)

    muscles
    |> Enum.filter(&(&1.role in [:primary, :secondary]))
    |> Enum.filter(&(node_id in CoverageWeighting.reached_nodes(&1.id)))
    |> Enum.max_by(&ExerciseTargets.role_rank(&1.role), fn -> nil end)
    |> case do
      nil -> []
      %{role: role} -> [%{exercise_ref: catalog_id, role: role}]
    end
  end
end
