defmodule MilosTraining.Feedback.Queries.ListReviewsForUser do
  alias MilosTraining.Feedback.FeedbackStore

  def call(user_id), do: FeedbackStore.list_reviews_for_user(user_id)
end
