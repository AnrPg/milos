defmodule Palee.Feedback.Queries.ReviewSummary do
  alias Palee.Feedback.FeedbackStore

  def call(filters), do: FeedbackStore.review_summary(filters)
end
