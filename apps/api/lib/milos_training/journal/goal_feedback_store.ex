defmodule MilosTraining.Journal.GoalFeedbackStore do
  @moduledoc """
  Facade over the configured goal-feedback adapter
  (`Journal.Ports.GoalFeedbackStore`, ADR-163). Every call runs inside a
  `RepoContext` session so the owner-only policy sees the acting member.
  """

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :goal_feedback_store)

  def feedback_entry(context, entry_kind, entry_id),
    do: RepoContext.run(context, fn -> adapter().feedback_entry(entry_kind, entry_id) end)

  def get_feedback(context, entry_kind, entry_id, user_id),
    do: RepoContext.run(context, fn -> adapter().get_feedback(entry_kind, entry_id, user_id) end)

  def list_feedback_for(context, scope),
    do: RepoContext.run(context, fn -> adapter().list_feedback_for(scope) end)

  # Called from inside a session the caller already opened (the journal
  # feed), like `JournalStore.list_comments/2`.
  def list_by_entries(entry_kind, entry_ids, user_id),
    do: adapter().list_by_entries(entry_kind, entry_ids, user_id)

  def put_feedback(context, attrs),
    do: RepoContext.run(context, fn -> adapter().put_feedback(attrs) end)
end
