defmodule MilosTraining.Feedback.Ports.FeedbackStore do
  @callback submit_review(Ecto.UUID.t(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback list_reviews_for_user(Ecto.UUID.t()) :: [map()]
  @callback list_reviews(map()) :: [map()]
  @callback update_review_status(Ecto.UUID.t(), String.t() | map()) ::
              {:ok, map()} | {:error, term()}
  @callback review_summary(map()) :: map()
end
