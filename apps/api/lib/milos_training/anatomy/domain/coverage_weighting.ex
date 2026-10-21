defmodule MilosTraining.Anatomy.Domain.CoverageWeighting do
  @moduledoc """
  How performed sets count towards the muscles of the taxonomy (ADR-164).
  The single policy behind the anatomy atlas and, later, muscle coverage
  (P3-M3). Pure.

  ## Weights
  A set of an exercise counts towards a muscle at the weight of the role the
  exercise gives it (`ExerciseTargets`):

    * `primary` - 1 set
    * `secondary` - half a set
    * `stabilizer` - nothing (holding position is not volume)

  ## Reach
  A target reaches the node it names, every node above it (a head reaches
  its group and region, a group its region) and, for a group, every head
  below it (the whole group works). A set counts **once per node**, at the
  strongest weight with which the exercise reaches that node, so a deadlift
  that trains the hamstrings and the glutes is still one set for the region
  «Hips and glutes» and one for «Thighs», never two.

  ## Levels
  Coverage levels compare weighted sets **per week** with fixed thresholds,
  so a 1-week and a 12-week range read the same way. They are indicators
  of how much a muscle was trained, not targets.
  """

  alias MilosTraining.Anatomy.Domain.{ExerciseTargets, MuscleTaxonomy}

  @role_weights %{primary: 1.0, secondary: 0.5, stabilizer: 0.0}

  # Weighted sets per week from which a level starts. Any set at all is
  # `low`; no set is `none`.
  @medium_from 3.0
  @high_from 8.0

  @levels ["none", "low", "medium", "high"]

  @ranges %{"1w" => 1, "4w" => 4, "12w" => 12}
  @default_range "4w"

  def role_weights, do: @role_weights

  def weight(role) when is_atom(role), do: Map.get(@role_weights, role, 0.0)
  def weight(role) when is_binary(role), do: weight(role_atom(role))

  def thresholds, do: %{medium: @medium_from, high: @high_from}
  def levels, do: @levels
  def ranges, do: Map.keys(@ranges) |> Enum.sort_by(&Map.fetch!(@ranges, &1))
  def default_range, do: @default_range

  @doc "`{:ok, range, weeks}` for a range token (`nil` means the default)."
  def parse_range(nil), do: parse_range(@default_range)
  def parse_range(""), do: parse_range(@default_range)

  def parse_range(range) when is_binary(range) do
    case Map.fetch(@ranges, range) do
      {:ok, weeks} -> {:ok, range, weeks}
      :error -> {:error, :invalid_range}
    end
  end

  def parse_range(_range), do: {:error, :invalid_range}

  @doc "The coverage level of `sets` weighted sets over `weeks` weeks."
  def level(sets, weeks) when is_number(sets) and is_integer(weeks) and weeks > 0 do
    per_week = sets / weeks

    cond do
      sets <= 0 -> "none"
      per_week >= @high_from -> "high"
      per_week >= @medium_from -> "medium"
      true -> "low"
    end
  end

  @reach (for node <- MuscleTaxonomy.nodes(), node.kind in [:group, :head], into: %{} do
            ancestors =
              case node.kind do
                :head -> [node.group_id, node.region_id]
                :group -> [node.region_id]
              end

            descendants =
              if node.kind == :group,
                do: node.id |> MuscleTaxonomy.children() |> Enum.map(& &1.id),
                else: []

            {node.id, Enum.uniq([node.id | ancestors] ++ descendants)}
          end)

  @doc "Every node a target (group or head) reaches; `[]` for an unknown id."
  def reached_nodes(target_id), do: Map.get(@reach, target_id, [])

  @doc """
  The weight one set of a catalog exercise adds to each node it reaches:
  `%{node_id => weight}`, stabilizers and zero weights left out. `%{}` for an
  unknown exercise.
  """
  def exercise_weights(catalog_id) do
    case ExerciseTargets.fetch(catalog_id) do
      %{muscles: muscles} -> node_weights(muscles)
      nil -> %{}
    end
  end

  @doc "Node weights of `[%{id, role}]` targets (strongest weight per node)."
  def node_weights(muscles) do
    Enum.reduce(muscles, %{}, fn %{id: id, role: role}, acc ->
      case weight(role) do
        w when w > 0 ->
          id
          |> reached_nodes()
          |> Enum.reduce(acc, fn node_id, inner -> Map.update(inner, node_id, w, &max(&1, w)) end)

        _zero ->
          acc
      end
    end)
  end

  @doc """
  The nodes one felt-feedback list touches (each node once): a felt head
  reaches its group and region, a felt group its heads and region, like sets.
  """
  def felt_nodes(felt_muscles) do
    felt_muscles
    |> List.wrap()
    |> Enum.flat_map(&reached_nodes/1)
    |> Enum.uniq()
  end

  defp role_atom("primary"), do: :primary
  defp role_atom("secondary"), do: :secondary
  defp role_atom("stabilizer"), do: :stabilizer
  defp role_atom(_role), do: nil
end
