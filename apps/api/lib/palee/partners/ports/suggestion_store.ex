defmodule Palee.Partners.Ports.SuggestionStore do
  @moduledoc """
  Persistence port of «Κλείστε μαζί» suggestions (ADR-280 §4). Personal
  rows: every call runs in the acting person's session (`app.user_id`), or a
  vendor's for the counters. The pair, blocked and shared-box reads answer
  only for an active match that includes the session user.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type point :: {float(), float()} | nil

  @doc "Both people of the match: Partners level, times and neighbourhood centroid."
  @callback pair(context, match_id :: id) :: [
              %{user_id: id, level: String.t() | nil, times: [String.t()], point: point}
            ]

  @doc "Which of `ids` either person of the match blocked or was blocked by."
  @callback blocked(context, match_id :: id, ids :: [id]) :: [id]

  @doc "Live boxes where both people hold an active membership."
  @callback shared_organizations(context, a :: id, b :: id) :: [id]

  @doc "Records (or changes) the person's «Δεν ταιριάζει» on a suggestion."
  @callback put_feedback(context, attrs :: map(), now :: DateTime.t()) ::
              {:ok, Palee.Partners.SuggestionFeedback.t()} | {:error, Ecto.Changeset.t()}

  @doc "Adds one to today's anonymous counter of `event`."
  @callback count(context, event :: String.t()) :: :ok

  @doc "Daily counters since `day` (inclusive): `[%{day, event, count}]`."
  @callback list_counters(context, since :: Date.t()) :: [
              %{day: Date.t(), event: String.t(), count: non_neg_integer()}
            ]

  @doc "Feedback answers since `at`, counted by reason: `%{reason => count}`."
  @callback feedback_reasons(context, since :: DateTime.t()) :: %{String.t() => non_neg_integer()}
end
