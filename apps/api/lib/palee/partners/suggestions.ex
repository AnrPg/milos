defmodule Palee.Partners.Suggestions do
  @moduledoc """
  The Partners context's public API for «Κλείστε μαζί» suggestions (ADR-280
  §4): the rule engine (`SuggestionPolicy`) and the suggestions store (the
  pair's facts, blocked organisers, shared boxes, feedback and the
  anonymous daily counters).
  """

  alias Palee.Partners.Domain.SuggestionPolicy
  alias Palee.Partners.SuggestionStore

  # The engine.
  defdelegate suggest(input), to: SuggestionPolicy
  defdelegate window(now), to: SuggestionPolicy
  defdelegate key(candidate), to: SuggestionPolicy
  defdelegate parse_key(key), to: SuggestionPolicy
  defdelegate check_feedback(params), to: SuggestionPolicy, as: :feedback
  defdelegate kinds(), to: SuggestionPolicy
  defdelegate feedback_reasons(), to: SuggestionPolicy
  defdelegate events(), to: SuggestionPolicy
  defdelegate default_km(), to: SuggestionPolicy
  defdelegate weights(), to: SuggestionPolicy

  # The store.
  defdelegate pair(context, match_id), to: SuggestionStore
  defdelegate blocked(context, match_id, ids), to: SuggestionStore
  defdelegate shared_organizations(context, a, b), to: SuggestionStore
  defdelegate put_feedback(context, attrs, now), to: SuggestionStore
  defdelegate count(context, event), to: SuggestionStore
  defdelegate list_counters(context, since), to: SuggestionStore
  defdelegate feedback_reasons(context, since), to: SuggestionStore
end
