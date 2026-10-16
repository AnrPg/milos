defmodule MilosTraining.Application.GetJournalFeed do
  @moduledoc """
  `GET /api/me/journal` (ADR-139 §9): the member's own journal across gyms,
  read in their personal session.
  """

  alias MilosTraining.Application.JournalFeed
  alias MilosTraining.Journal

  def call(%{user_id: user_id} = context, params) when is_map(params),
    do: Journal.with_context(context, fn -> JournalFeed.page(user_id, :owner, params) end)
end
