defmodule Palee.Interests do
  @moduledoc """
  What a person does (ADR-183): the disciplines they train and their level,
  asked once by the first-run and editable in Εγώ › Ρυθμίσεις. Personal
  account data, never a gym's: only its owner reads or writes it. Γύρω μου
  and Partners read it to suggest, never to filter on their own.
  """

  alias Palee.Interests.Domain.InterestsPolicy
  alias Palee.Interests.InterestsStore

  defdelegate levels, to: InterestsPolicy
  defdelegate max_disciplines, to: InterestsPolicy
  defdelegate normalize(params, disciplines), to: InterestsPolicy

  @doc "The person's interests; an empty set when they never said."
  def get(context), do: InterestsStore.get(context) || InterestsPolicy.empty()

  @doc "Replaces the person's interests with already normalized `attrs`."
  defdelegate put(context, attrs, now), to: InterestsStore
end
