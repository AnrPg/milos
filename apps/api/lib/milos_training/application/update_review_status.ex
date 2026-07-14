defmodule MilosTraining.Application.UpdateReviewStatus do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Feedback, Identity}

  def call(id, params) do
    status = params["status"] || params[:status]

    if is_binary(status) do
      with {:ok, review} <- Feedback.update_review_status(id, params) do
        broadcast_review_status_updated(review)
        {:ok, review}
      end
    else
      {:error, :bad_request}
    end
  end

  defp broadcast_review_status_updated(review) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)
    user_id = Map.get(review, :user_id) || Map.get(review, "user_id")

    BroadcastUserSync.for_users(admin_ids, ["admin_reviews"],
      reason: "review_status_updated",
      payload: %{review_id: review.id}
    )

    if user_id,
      do:
        BroadcastUserSync.for_user(user_id, ["my_reviews"],
          reason: "review_status_updated",
          payload: %{review_id: review.id}
        )
  end
end
