defmodule Palee.Feedback.Queries.ListReviews do
  alias Palee.Feedback.FeedbackStore

  def call(filters), do: FeedbackStore.list_reviews(filters)
end
