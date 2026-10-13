defmodule MilosTraining.Application.SubmitFormReview do
  @moduledoc """
  A client asks for technique feedback on a video (ADR-098). One `form_reviews`
  unit is reserved until a coach reviews (finalize) or the client withdraws
  (release). Staff are notified.
  """

  alias MilosTraining.{Coaching, Finance, Notifications, Organizations}
  alias MilosTraining.Coaching.Domain.FormReviewPolicy

  def call(context, %{id: user_id} = actor, params) do
    id = Ecto.UUID.generate()

    request =
      id
      |> FormReviewPolicy.entitlement_request(Date.utc_today())
      |> Map.put(:actor_role, actor.role)

    with {:ok, reservation} <- Finance.reserve_entitlement(context, user_id, request) do
      attrs = %{
        id: id,
        user_id: user_id,
        video_url: value(params, :video_url),
        note: value(params, :note),
        exercise_name: value(params, :exercise_name),
        execution_id: value(params, :execution_id),
        reservation_id: Map.get(reservation, :id)
      }

      case Coaching.create_form_review(context, attrs) do
        {:ok, review} ->
          notify_staff(context, review, actor)
          {:ok, review}

        {:error, reason} ->
          release(context, reservation, id)
          {:error, reason}
      end
    end
  end

  defp notify_staff(context, review, actor) do
    context.organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.each(fn staff_id ->
      Notifications.process_event("form_review_submitted", %{
        user_id: staff_id,
        form_review_id: review.id,
        client_nickname: Map.get(actor, :nickname),
        exercise_name: review.exercise_name
      })
    end)
  end

  defp release(_context, %{id: nil}, _id), do: :ok

  defp release(context, %{id: reservation_id}, id) do
    _result =
      Finance.release_entitlement(context, reservation_id, %{
        reason: "Form review was not recorded",
        idempotency_key: "form-review-release:#{id}"
      })

    :ok
  end

  defp release(_context, _reservation, _id), do: :ok

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
