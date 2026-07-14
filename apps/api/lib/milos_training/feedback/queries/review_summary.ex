defmodule MilosTraining.Feedback.Queries.ReviewSummary do
  alias MilosTraining.Feedback.FeedbackStore

  def call(filters), do: FeedbackStore.review_summary(filters)
end
