defmodule MilosTraining.Application.GetPRHistory do
  alias MilosTraining.Pantheon.PRStore

  def call(id, user_id) do
    case PRStore.get_pr_for_user(id, user_id) do
      nil -> {:error, :not_found}
      _pr -> {:ok, PRStore.list_pr_history(id)}
    end
  end
end
