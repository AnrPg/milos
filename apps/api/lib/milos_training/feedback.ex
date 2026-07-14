defmodule MilosTraining.Feedback do
  alias MilosTraining.Feedback.Commands.{SubmitReview, UpdateReviewStatus}
  alias MilosTraining.Feedback.Queries.{ListReviews, ListReviewsForUser, ReviewSummary}

  defdelegate submit_review(user_id, params), to: SubmitReview, as: :call
  defdelegate list_reviews_for_user(user_id), to: ListReviewsForUser, as: :call
  defdelegate list_reviews(filters \\ %{}), to: ListReviews, as: :call
  defdelegate update_review_status(review_id, status), to: UpdateReviewStatus, as: :call
  defdelegate review_summary(filters \\ %{}), to: ReviewSummary, as: :call
end
