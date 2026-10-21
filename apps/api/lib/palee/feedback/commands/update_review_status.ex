defmodule Palee.Feedback.Commands.UpdateReviewStatus do
  alias Palee.Feedback.FeedbackStore

  def call(review_id, params), do: FeedbackStore.update_review_status(review_id, params)
end
