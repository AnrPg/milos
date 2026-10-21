defmodule MilosTraining.Insights.InsightStore do
  @moduledoc "Dispatches the Insights persistence port to the configured adapter."

  @behaviour MilosTraining.Insights.Ports.InsightStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list(user_id), do: adapter().list(user_id)

  @impl true
  def put_results(user_id, results, from, to, now),
    do: adapter().put_results(user_id, results, from, to, now)

  @impl true
  def dismiss(user_id, rule, now), do: adapter().dismiss(user_id, rule, now)

  @impl true
  def restore(user_id), do: adapter().restore(user_id)

  @impl true
  def delete_all(user_id), do: adapter().delete_all(user_id)

  @impl true
  def candidates(since, after_id, limit), do: adapter().candidates(since, after_id, limit)

  defp adapter, do: Application.fetch_env!(:milos_training, :insight_store)
end
