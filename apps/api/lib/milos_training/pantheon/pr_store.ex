defmodule MilosTraining.Pantheon.PRStore do
  @behaviour MilosTraining.Pantheon.Ports.PRStore

  defp adapter do
    Application.fetch_env!(:milos_training, :pr_store)
  end

  @impl true
  def list_user_prs(user_id), do: adapter().list_user_prs(user_id)

  @impl true
  def search_user_prs(user_id, query), do: adapter().search_user_prs(user_id, query)

  @impl true
  def get_pr(id), do: adapter().get_pr(id)

  @impl true
  def get_pr_for_user(id, user_id), do: adapter().get_pr_for_user(id, user_id)

  @impl true
  def create_pr(params), do: adapter().create_pr(params)

  @impl true
  def update_pr(id, params), do: adapter().update_pr(id, params)

  @impl true
  def edit_pr(id, params), do: adapter().edit_pr(id, params)

  @impl true
  def delete_pr(id, user_id), do: adapter().delete_pr(id, user_id)

  @impl true
  def list_pr_history(pr_record_id), do: adapter().list_pr_history(pr_record_id)

  @impl true
  def count_user_prs(user_id), do: adapter().count_user_prs(user_id)
end
