defmodule Palee.Feedback.Commands.SubmitReview do
  alias Palee.Feedback.FeedbackStore

  def call(user_id, params), do: FeedbackStore.submit_review(user_id, params)
end
