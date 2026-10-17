defmodule MilosTraining.Infrastructure.Journal.FeedScope do
  @moduledoc """
  Whose entries one journal source lists (ADR-139 §6, §9): the member's own,
  in the member's session (`:owner`), or the entries a coach of one gym may
  read (`{:coach, organization_id}`): recorded in that gym and on a rung that
  reaches the coach. Kinds the coach always sees (injuries) or that are a
  rung of their own (reviews) pass `rung?: false`.
  """

  import Ecto.Query

  def apply(query, user_id, scope, opts \\ [])

  def apply(query, user_id, :owner, _opts), do: where(query, [row], row.user_id == ^user_id)

  def apply(query, user_id, {:coach, organization_id}, opts) do
    query =
      where(
        query,
        [row],
        row.user_id == ^user_id and row.organization_id == ^organization_id
      )

    if Keyword.get(opts, :rung?, true) do
      where(
        query,
        [row],
        fragment("milos_journal_visibility_reaches_coach(?)", row.journal_visibility)
      )
    else
      query
    end
  end
end
