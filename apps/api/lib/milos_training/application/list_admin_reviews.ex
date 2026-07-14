defmodule MilosTraining.Application.ListAdminReviews do
  alias MilosTraining.Feedback

  def call(params), do: {:ok, %{reviews: Feedback.list_reviews(params)}}
end
