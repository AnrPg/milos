defmodule MilosTraining.Feedback.Queries.ListReviews do
  alias MilosTraining.Feedback.FeedbackStore

  def call(filters), do: FeedbackStore.list_reviews(filters)
end
