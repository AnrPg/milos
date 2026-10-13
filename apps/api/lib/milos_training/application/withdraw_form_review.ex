defmodule MilosTraining.Application.WithdrawFormReview do
  @moduledoc "A client withdraws an open form review; the unit is given back (ADR-098)."

  alias MilosTraining.{Coaching, Finance}
  alias MilosTraining.Coaching.Domain.FormReviewPolicy

  def call(context, %{id: user_id}, id) do
    with %{} = review <- Coaching.get_form_review(context, id) || {:error, :not_found},
         :ok <- FormReviewPolicy.can_withdraw?(review, user_id),
         {:ok, withdrawn} <- Coaching.withdraw_form_review(context, id) do
      release(context, withdrawn)
      {:ok, withdrawn}
    end
  end

  defp release(_context, %{reservation_id: nil}), do: :ok

  defp release(context, %{reservation_id: reservation_id, id: id}) do
    _result =
      Finance.release_entitlement(context, reservation_id, %{
        reason: "Form review withdrawn",
        idempotency_key: "form-review-withdraw:#{id}"
      })

    :ok
  end
end
