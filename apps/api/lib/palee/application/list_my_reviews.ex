defmodule Palee.Application.ListMyReviews do
  alias Palee.Feedback

  def call(user_id), do: {:ok, %{reviews: Feedback.list_reviews_for_user(user_id)}}
end
