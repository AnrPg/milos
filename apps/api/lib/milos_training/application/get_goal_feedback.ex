defmodule MilosTraining.Application.GetGoalFeedback do
  @moduledoc """
  «Τι ένιωσες» read (ADR-163): for one of the member's own entries, the
  member-visible goals of its workout (if any) and what they said they felt
  (if they did). A voided entry still returns its feedback, flagged
  `voided`; feeds and analytics ignore voided entries.
  """

  alias MilosTraining.Application.GoalFeedbackEntry
  alias MilosTraining.Journal

  def call(context, entry_kind, entry_id) do
    with {:ok, entry} <- GoalFeedbackEntry.fetch(context, entry_kind, entry_id) do
      feedback =
        Journal.get_goal_feedback(context, entry.entry_kind, entry.entry_id, context.user_id)

      {:ok, GoalFeedbackEntry.response(context, entry, feedback)}
    end
  end
end
