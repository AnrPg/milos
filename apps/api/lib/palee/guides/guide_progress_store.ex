defmodule Palee.Guides.GuideProgressStore do
  @moduledoc "Facade over the walkthrough-progress adapter; every call runs in the person's `RepoContext` session (ADR-193)."

  @behaviour Palee.Guides.Ports.GuideProgressStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :guide_progress_store)

  defp run(context, function, args),
    do: RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)

  @impl true
  def list(context), do: run(context, :list, [])
  @impl true
  def update(context, guide_id, now, fun), do: run(context, :update, [guide_id, now, fun])
  @impl true
  def delete(context, guide_id), do: run(context, :delete, [guide_id])
end
