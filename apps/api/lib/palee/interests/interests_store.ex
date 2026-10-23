defmodule Palee.Interests.InterestsStore do
  @moduledoc "Facade over the interests adapter; every call runs in the person's `RepoContext` session (ADR-183)."

  @behaviour Palee.Interests.Ports.InterestsStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :interests_store)

  @impl true
  def get(context), do: RepoContext.run(context, fn -> adapter().get(context) end)

  @impl true
  def put(context, attrs, now),
    do: RepoContext.run(context, fn -> adapter().put(context, attrs, now) end)
end
