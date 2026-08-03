defmodule MilosTraining.Application.SubmitReview do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent}
  alias MilosTraining.Feedback.Domain.ReviewEligibility

  alias MilosTraining.{
    Analytics,
    Execution,
    Feedback,
    Finance,
    Identity,
    Notifications,
    Scheduling,
    Workouts
  }

  def call(user_id, params) do
    with {:ok, target_snapshot} <- target_snapshot(user_id, params),
         {:ok, review} <-
           Feedback.submit_review(user_id, trusted_review_params(params, target_snapshot)) do
      RecordAnalyticsEvent.call_unsafe("review_submitted", %{
        user_id: user_id,
        context_type: "review",
        context_id: review.id,
        metadata: %{
          target_type: review.target_type,
          target_id: review.target_id,
          rating: review.rating,
          sentiment: review.sentiment,
          status: review.status
        }
      })

      broadcast_review_submitted(user_id, review.id)
      dispatch_review_notification(user_id, review)

      {:ok, review}
    end
  end

  defp dispatch_review_notification(user_id, review) do
    Notifications.dispatch_event(:review_submitted, %{
      review_id: review.id,
      user_id: user_id,
      target_type: review.target_type,
      target_id: review.target_id,
      rating: review.rating,
      body: review.body
    })
  end

  defp target_snapshot(user_id, params) do
    target_type = params[:target_type] || params["target_type"]
    target_id = params[:target_id] || params["target_id"]

    case {target_type, target_id} do
      {type, nil}
      when type in ["app", "general", "gym_parameter", "coaching_parameter", "private_coaching"] ->
        normalized_type = normalize_target_type(type)
        {:ok, snapshot(normalized_type, nil, target_label(type))}

      {type, _id}
      when type in ["app", "general", "gym_parameter", "coaching_parameter", "private_coaching"] ->
        {:error, :review_target_must_be_global}

      {type, nil}
      when type in ["workout", "execution", "exercise", "class_slot", "membership_package"] ->
        {:error, :review_target_required}

      {"workout", id} ->
        case {Workouts.get_workout(id), workout_execution_status(user_id, id)} do
          {nil, _status} -> {:error, :review_target_not_found}
          {_workout, :missing} -> {:error, :review_target_not_found}
          {_workout, :incomplete} -> {:error, :review_target_not_completed}
          {workout, :completed} -> {:ok, snapshot("workout", id, workout[:title])}
        end

      {"execution", id} ->
        case Execution.get_execution_for_user(id, user_id) do
          nil ->
            {:error, :review_target_not_found}

          execution ->
            if ReviewEligibility.completed_execution?(execution) do
              {:ok, snapshot("execution", id, execution[:status])}
            else
              {:error, :review_target_not_completed}
            end
        end

      {"exercise", id} ->
        case {Workouts.exercise_exists?(id), exercise_execution_status(user_id, id)} do
          {false, _status} -> {:error, :review_target_not_found}
          {_exists?, :missing} -> {:error, :review_target_not_found}
          {_exists?, :incomplete} -> {:error, :review_target_not_completed}
          {_exists?, :completed} -> {:ok, snapshot("exercise", id, "Exercise")}
        end

      {"class_slot", id} ->
        case {Scheduling.get_slot(id), class_slot_status(user_id, id)} do
          {nil, _status} -> {:error, :review_target_not_found}
          {_slot, :missing} -> {:error, :review_target_not_found}
          {_slot, :incomplete} -> {:error, :review_target_not_completed}
          {slot, :attended} -> {:ok, snapshot("class_slot", id, slot[:training_type])}
        end

      {"membership_package", id} ->
        case {Finance.get_package(id), user_has_membership_package?(user_id, id)} do
          {nil, _interacted?} ->
            {:error, :review_target_not_found}

          {_package, false} ->
            {:error, :review_target_not_found}

          {package, true} ->
            {:ok, snapshot("membership_package", id, package[:name] || package[:code])}
        end

      {_type, _id} ->
        {:error, :review_target_not_found}
    end
  end

  defp trusted_review_params(params, target_snapshot) do
    params
    |> string_key_map()
    |> Map.drop(["target_snapshot"])
    |> Map.put("target_snapshot", target_snapshot)
  end

  defp snapshot(type, id, label) do
    %{
      "target_type" => type,
      "target_id" => id,
      "label" => label || target_label(type),
      "captured_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp target_label("private_coaching"), do: "Private coaching"
  defp target_label(type) when is_binary(type), do: String.replace(type, "_", " ")
  defp target_label(_type), do: "Review target"

  defp normalize_target_type("private_coaching"), do: "coaching_parameter"
  defp normalize_target_type(type), do: type

  defp workout_execution_status(user_id, workout_id) do
    user_id
    |> Execution.list_executions_for_user()
    |> Enum.filter(&(&1.master_workout_id == workout_id))
    |> completion_status()
  end

  defp exercise_execution_status(user_id, exercise_id) do
    user_id
    |> Execution.list_executions_for_user()
    |> Enum.filter(fn execution ->
      exercise_id in (execution.checked_exercise_ids || []) or
        Enum.any?(execution.exercise_notes || [], fn note ->
          (note[:exercise_id] || note["exercise_id"]) == exercise_id
        end)
    end)
    |> completion_status()
  end

  defp completion_status([]), do: :missing

  defp completion_status(executions) do
    if Enum.any?(executions, &ReviewEligibility.completed_execution?/1) do
      :completed
    else
      :incomplete
    end
  end

  defp class_slot_status(user_id, slot_id) do
    case Scheduling.get_slot(slot_id) do
      %{bookings: bookings} when is_list(bookings) ->
        if approved_booking_for_user?(bookings, user_id) do
          slot_attendance_status(user_id, slot_id)
        else
          :missing
        end

      _slot ->
        :missing
    end
  end

  defp approved_booking_for_user?(bookings, user_id) do
    Enum.any?(bookings, fn booking ->
      booking.user_id == user_id and to_string(booking.status) == "approved"
    end)
  end

  defp slot_attendance_status(user_id, slot_id) do
    case Analytics.get_attendance_for_user_class(user_id, slot_id) do
      attendance when not is_nil(attendance) ->
        if ReviewEligibility.attended_class?(attendance), do: :attended, else: :incomplete

      nil ->
        :incomplete
    end
  end

  defp user_has_membership_package?(user_id, package_id) do
    case Finance.get_member_profile(user_id) do
      %{package_subscriptions: subscriptions} when is_list(subscriptions) ->
        Enum.any?(subscriptions, &(&1.membership_package_id == package_id))

      _profile ->
        false
    end
  end

  defp string_key_map(params) when is_map(params) do
    Map.new(params, fn {key, value} -> {to_string(key), value} end)
  end

  defp broadcast_review_submitted(user_id, review_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_user(user_id, ["my_reviews"],
      reason: "review_submitted",
      payload: %{review_id: review_id}
    )

    BroadcastUserSync.for_users(admin_ids, ["admin_reviews"],
      reason: "review_submitted",
      payload: %{user_id: user_id, review_id: review_id}
    )
  end
end
