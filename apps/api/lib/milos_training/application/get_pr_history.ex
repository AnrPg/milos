defmodule MilosTraining.Application.GetPRHistory do
  alias MilosTraining.Pantheon
  alias MilosTraining.Pantheon.PRStore

  # Owner-only under RLS: runs in the acting user's scope (ADR-119).
  def call(%{user_id: user_id} = context, id),
    do: Pantheon.with_user_context(context, fn -> call(id, user_id) end)

  def call(id, user_id) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil -> {:error, :not_found}
      _pr -> {:ok, PRStore.list_pr_history(id)}
    end
  end
end
