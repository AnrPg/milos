defmodule MilosTraining.Application.SubmitReview do
  alias MilosTraining.Application.{BroadcastUserSync, RecordAnalyticsEvent, TenantStaffRecipients}
  alias MilosTraining.Feedback.Domain.ReviewEligibility

  alias MilosTraining.{
    Analytics,
    Execution,
    Feedback,
    Finance,
    Journal,
    Notifications,
    Scheduling,
    Workouts
  }

  def call(context, user_id, params) do
    with {:ok, target_snapshot} <- target_snapshot(context, user_id, params),
         {:ok, review} <-
           Feedback.submit_review(
             user_id,
             trusted_review_params(params, target_snapshot, context)
           ) do
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

      broadcast_review_submitted(user_id, review)
      dispatch_review_notification(user_id, review)

      {:ok, review}
    end
  end

  def call(user_id, params), do: call(nil, user_id, params)

  defp dispatch_review_notification(user_id, review) do
    Notifications.dispatch_event(:review_submitted, %{
      review_id: review.id,
      user_id: user_id,
      organization_id: review.organization_id,
      target_type: review.target_type,
      target_id: review.target_id,
      rating: review.rating,
      body: review.body
    })
  end

  defp target_snapshot(context, user_id, params) do
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
        case {get_workout(context, id), workout_execution_status(user_id, id)} do
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
        case {exercise_exists?(context, id), exercise_execution_status(user_id, id)} do
          {false, _status} -> {:error, :review_target_not_found}
          {_exists?, :missing} -> {:error, :review_target_not_found}
          {_exists?, :incomplete} -> {:error, :review_target_not_completed}
          {_exists?, :completed} -> {:ok, snapshot("exercise", id, "Exercise")}
        end

      {"class_slot", id} ->
        case {get_slot(context, id), class_slot_status(context, user_id, id)} do
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

  defp trusted_review_params(params, target_snapshot, context) do
    params
    |> string_key_map()
    |> Map.drop(["target_snapshot"])
    |> Map.put("target_snapshot", target_snapshot)
    |> put_organization_id(context)
  end

  defp put_organization_id(params, %{organization_id: organization_id})
       when is_binary(organization_id),
       do: Map.put(params, "organization_id", organization_id)

  defp put_organization_id(params, _context), do: params

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

  defp normalize_target_type("private_coaching"), do: "coaching_parameter"
  defp normalize_target_type(type), do: type

  defp workout_execution_status(user_id, workout_id) do
    user_id
    |> Execution.list_executions_for_user()
    |> Enum.filter(&(&1.master_workout_id == workout_id))
    |> completion_status()
  end

  defp exercise_execution_status(user_id, exercise_id) do
    executions = Execution.list_executions_for_user(user_id)
    commented = Journal.comments_by_entry("execution", Enum.map(executions, & &1.id))

    executions
    |> Enum.filter(fn execution ->
      exercise_id in (execution.checked_exercise_ids || []) or
        Enum.any?(Map.get(commented, execution.id, []), &(&1.exercise_id == exercise_id))
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

  defp class_slot_status(context, user_id, slot_id) do
    case get_slot(context, slot_id) do
      %{bookings: bookings} when is_list(bookings) ->
        if approved_booking_for_user?(bookings, user_id) do
          slot_attendance_status(context, user_id, slot_id)
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

  defp slot_attendance_status(context, user_id, slot_id) do
    case get_attendance(context, user_id, slot_id) do
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

  # Workouts and their exercises are tenant data: without a tenant context a
  # workout or exercise target is not found (ADR-133).
  defp get_workout(%{organization_id: organization_id} = context, id)
       when is_binary(organization_id) do
    case Workouts.get_workout(context, id) do
      %{} = workout -> workout
      _missing -> nil
    end
  end

  defp get_workout(_context, _id), do: nil

  defp exercise_exists?(%{organization_id: organization_id} = context, id)
       when is_binary(organization_id),
       do: Workouts.exercise_exists?(context, id) == true

  defp exercise_exists?(_context, _id), do: false

  defp get_slot(%{organization_id: _} = context, id), do: Scheduling.get_slot(context, id)
  defp get_slot(_context, _id), do: nil

  defp get_attendance(%{organization_id: _} = context, user_id, slot_id),
    do: Analytics.get_attendance_for_user_class(context, user_id, slot_id)

  defp get_attendance(_context, _user_id, _slot_id), do: nil

  defp broadcast_review_submitted(user_id, review) do
    review_id = review.id
    admin_ids = TenantStaffRecipients.user_ids(review)

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
