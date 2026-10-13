defmodule MilosTraining.Application.GetMyProgress do
  @moduledoc "Advanced progress statistics of the client's own training in this gym (ADR-098)."

  alias MilosTraining.Analytics.Domain.ProgressStats
  alias MilosTraining.Application.{AuthorizePackageFeature, ListWorkoutExecutions}
  alias MilosTraining.Pantheon

  def call(%{organization_id: organization_id} = context, actor) do
    with :ok <- AuthorizePackageFeature.call(context, actor, :view_advanced_analytics),
         {:ok, executions} <- ListWorkoutExecutions.call(context, actor.id) do
      executions
      |> Enum.filter(&(&1.organization_id == organization_id))
      |> ProgressStats.build(Date.utc_today())
      |> Map.put(
        :pr_timeline,
        pr_timeline(context, actor.id)
      )
      |> then(&{:ok, &1})
    end
  end

  # Personal records are RLS-protected per user (ADR-129).
  defp pr_timeline(context, user_id) do
    Pantheon.with_user_context(context, fn ->
      ProgressStats.pr_timeline(
        Pantheon.list_user_record_history(user_id),
        Pantheon.list_records(user_id)
      )
    end)
  end
end
