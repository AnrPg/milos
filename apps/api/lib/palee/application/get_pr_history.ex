defmodule Palee.Application.GetPRHistory do
  alias Palee.Pantheon
  alias Palee.Pantheon.PRStore

  # Owner-only under RLS: runs in the acting user's scope (ADR-129).
  def call(%{user_id: user_id} = context, id),
    do: Pantheon.with_user_context(context, fn -> call(id, user_id) end)

  def call(id, user_id) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil -> {:error, :not_found}
      _pr -> {:ok, PRStore.list_pr_history(id)}
    end
  end

  @doc """
  Every superseded score of every PR the member owns, oldest first, in one
  read (ADR-194): Πρόοδος draws each lift's trend and the benchmarks'
  «retest» hint from it instead of one request per PR.
  """
  def all(%{user_id: user_id} = context) do
    Pantheon.with_user_context(context, fn ->
      {:ok,
       user_id
       |> PRStore.list_user_pr_history()
       |> Enum.map(
         &Map.take(&1, [:id, :pr_record_id, :score, :beaten_on, :supporting_metrics, :inserted_at])
       )}
    end)
  end
end
