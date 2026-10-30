defmodule Palee.Partners.SuggestionStore do
  @moduledoc """
  Facade over the configured «Κλείστε μαζί» suggestions adapter (ADR-280
  §4, config `:palee, :partner_suggestion_store`). Every call runs inside a
  `RepoContext` session of the acting person (or vendor) alone: these rows
  are personal, never a gym's.
  """

  @behaviour Palee.Partners.Ports.SuggestionStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :partner_suggestion_store)

  defp personal(context, function, args) do
    scope = %{user_id: Map.fetch!(context, :user_id)}
    RepoContext.run(scope, fn -> apply(adapter(), function, [scope | args]) end)
  end

  @impl true
  def pair(context, match_id), do: personal(context, :pair, [match_id])

  @impl true
  def blocked(_context, _match_id, []), do: []
  def blocked(context, match_id, ids), do: personal(context, :blocked, [match_id, ids])

  @impl true
  def shared_organizations(context, a, b), do: personal(context, :shared_organizations, [a, b])

  @impl true
  def put_feedback(context, attrs, now), do: personal(context, :put_feedback, [attrs, now])

  @impl true
  def count(context, event), do: personal(context, :count, [event])

  @impl true
  def list_counters(context, since), do: personal(context, :list_counters, [since])

  @impl true
  def feedback_reasons(context, since), do: personal(context, :feedback_reasons, [since])
end
