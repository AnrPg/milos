defmodule MilosTraining.Feedback.FeedbackStore do
  @behaviour MilosTraining.Feedback.Ports.FeedbackStore

  @adapter Application.compile_env(
             :milos_training,
             :feedback_store,
             MilosTraining.Infrastructure.Feedback.EctoFeedbackStore
           )

  defdelegate submit_review(user_id, params), to: @adapter
  defdelegate list_reviews_for_user(user_id), to: @adapter
  defdelegate list_reviews(filters), to: @adapter
  defdelegate update_review_status(review_id, status), to: @adapter
  defdelegate review_summary(filters), to: @adapter
end
