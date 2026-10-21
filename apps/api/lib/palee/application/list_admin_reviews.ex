defmodule Palee.Application.ListAdminReviews do
  alias Palee.Feedback

  def call(params), do: {:ok, %{reviews: Feedback.list_reviews(params)}}
end
