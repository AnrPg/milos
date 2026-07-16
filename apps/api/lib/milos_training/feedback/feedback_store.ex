defmodule MilosTraining.Feedback.FeedbackStore do
  @behaviour MilosTraining.Feedback.Ports.FeedbackStore

  def submit_review(user_id, params), do: adapter().submit_review(user_id, params)
  def list_reviews_for_user(user_id), do: adapter().list_reviews_for_user(user_id)
  def list_reviews(filters), do: adapter().list_reviews(filters)

  def update_review_status(review_id, status),
    do: adapter().update_review_status(review_id, status)

  def review_summary(filters), do: adapter().review_summary(filters)

  defp adapter, do: Application.fetch_env!(:milos_training, :feedback_store)
end
