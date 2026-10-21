defmodule Palee.Application.CompleteFormReview do
  @moduledoc "A coach answers a form review; the reserved unit is used (ADR-098)."

  alias Palee.{Coaching, Finance, Notifications}
  alias Palee.Application.AuthorizeClientAccess
  alias Palee.Coaching.Domain.FormReviewPolicy

  def call(context, %{id: reviewer_id}, id, feedback) do
    with %{} = review <- Coaching.get_form_review(context, id) || {:error, :not_found},
         :ok <- AuthorizeClientAccess.call(context, :manage_coaching, review.user_id),
         :ok <- FormReviewPolicy.can_review?(review),
         {:ok, reviewed} <-
           Coaching.complete_form_review(context, id, %{
             reviewer_id: reviewer_id,
             feedback: feedback,
             reviewed_at: DateTime.utc_now()
           }) do
      finalize(context, reviewed)

      Notifications.process_event("form_review_completed", %{
        user_id: reviewed.user_id,
        form_review_id: reviewed.id,
        exercise_name: reviewed.exercise_name
      })

      {:ok, reviewed}
    end
  end

  defp finalize(_context, %{reservation_id: nil}), do: :ok

  defp finalize(context, %{reservation_id: reservation_id, id: id}) do
    _result =
      Finance.finalize_entitlement(context, reservation_id, %{
        reason: "Form review completed",
        idempotency_key: "form-review-finalize:#{id}"
      })

    :ok
  end
end
