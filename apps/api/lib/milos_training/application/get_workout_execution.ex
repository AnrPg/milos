defmodule MilosTraining.Application.GetWorkoutExecution do
  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.{Organizations, Workouts}

  @staff_roles [:owner, :admin, :coach]

  def call(context, execution_id, actor) do
    ExecutionStore.with_authorization_context(context, fn ->
      with %{} = execution <- Execution.get_execution(execution_id) || {:error, :not_found},
           :ok <- authorize_execution_access(execution, actor) do
        {:ok, attach_workout_summary(execution, execution_context(context, execution, actor))}
      end
    end)
  end

  def call(execution_id, actor) do
    ExecutionStore.with_user_context(%{user_id: actor.id, account: actor}, fn ->
      with %{} = execution <-
             Execution.get_execution_for_user(execution_id, actor.id) || {:error, :not_found} do
        {:ok, attach_workout_summary(execution, execution_context(nil, execution, actor))}
      end
    end)
  end

  defp authorize_execution_access(%{user_id: user_id}, %{id: user_id}), do: :ok

  defp authorize_execution_access(%{organization_id: organization_id}, actor) do
    actor.id
    |> Organizations.list_memberships()
    |> Enum.any?(fn %{membership: membership, organization: organization} ->
      organization.id == organization_id and membership.status == :active and
        membership.role in @staff_roles
    end)
    |> if(do: :ok, else: {:error, :not_found})
  end

  defp execution_context(
         %{organization_id: organization_id} = context,
         %{organization_id: organization_id},
         _actor
       ),
       do: context

  defp execution_context(_context, %{organization_id: organization_id}, actor) do
    case Enum.find(Organizations.list_memberships(actor.id), fn membership ->
           membership.organization.id == organization_id and
             membership.membership.status == :active
         end) do
      nil ->
        nil

      %{membership: membership} ->
        %{
          organization_id: organization_id,
          user_id: actor.id,
          role: membership.role,
          request_metadata: %{source: :execution_read}
        }
    end
  end

  defp attach_workout_summary(execution, context) do
    case fetch_workout(context, execution.master_workout_id) do
      nil ->
        Map.merge(execution, %{
          workout_title: "Deleted workout",
          workout_type: nil,
          section_scores: attach_section_names(execution.section_scores || [], %{})
        })

      workout ->
        presented_workout =
          case execution.scale_level_slug do
            nil -> workout
            scale_slug -> Workouts.materialize_workout_for_scale(workout.id, scale_slug)
          end

        Map.merge(execution, %{
          workout_title: workout.title,
          workout_type: workout.type,
          workout: presented_workout,
          section_scores:
            attach_section_names(execution.section_scores || [], section_name_lookup(workout))
        })
    end
  end

  defp fetch_workout(_context, nil), do: nil
  defp fetch_workout(nil, _workout_id), do: nil
  defp fetch_workout(context, workout_id), do: Workouts.get_workout(context, workout_id)

  defp attach_section_names(section_scores, lookup) do
    Enum.map(section_scores, fn score ->
      Map.put(score, :section_name, Map.get(lookup, score[:section_id] || score["section_id"]))
    end)
  end

  defp section_name_lookup(workout) do
    workout.sections
    |> Enum.map(fn section -> {section.id, section.name} end)
    |> Map.new()
  end
end
