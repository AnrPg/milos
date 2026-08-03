defmodule MilosTraining.FeedbackTest do
  use MilosTraining.DataCase

  alias MilosTraining.Application.SubmitReview
  alias MilosTraining.{Analytics, Execution, Feedback, Notifications}
  alias MilosTraining.TestFixtures

  test "submits a review with questionnaire answers and updates status" do
    user = TestFixtures.user_fixture()

    assert {:ok, review} =
             Feedback.submit_review(user.id, %{
               target_type: "workout",
               rating: 4,
               sentiment: "positive",
               body: "Good session pacing.",
               answers: [
                 %{
                   question_key: "difficulty_fit",
                   question_text: "Was the difficulty appropriate?",
                   answer_text: "Right level",
                   rating_value: 4
                 }
               ]
             })

    assert review.rating == 4
    assert [%{question_key: "difficulty_fit"}] = review.answers

    assert {:ok, reviewed} = Feedback.update_review_status(review.id, "reviewed")
    assert reviewed.status == "reviewed"
  end

  test "moderation can mark follow-up tags" do
    user = TestFixtures.user_fixture()

    assert {:ok, review} =
             Feedback.submit_review(user.id, %{
               target_type: "general",
               sentiment: "neutral",
               answers: [
                 %{
                   question_key: "general",
                   question_text: "How was the app?",
                   answer_text: "Needs a staff check"
                 }
               ]
             })

    assert {:ok, updated} =
             Feedback.update_review_status(review.id, %{
               status: "needs_follow_up",
               tags: ["programming", "pain"]
             })

    assert updated.status == "needs_follow_up"
    assert updated.tags == ["programming", "pain"]
  end

  test "normalizes legacy coaching target alias and rejects unknown target types" do
    user = TestFixtures.user_fixture()

    assert {:ok, review} =
             Feedback.submit_review(user.id, %{
               target_type: "private_coaching",
               rating: 5,
               sentiment: "positive",
               answers: [
                 %{
                   question_key: "ability_match",
                   question_text: "How well did this workout match your current ability today?",
                   answer_text: "It matched well",
                   rating_value: 5
                 },
                 %{
                   question_key: "useful_part",
                   question_text: "Which part felt most useful or enjoyable?",
                   answer_text: "The main lift"
                 },
                 %{
                   question_key: "hard_part",
                   question_text: "Which part felt too hard, painful, confusing, or unnecessary?",
                   answer_text: "Nothing painful"
                 },
                 %{
                   question_key: "next_adjustment",
                   question_text: "What should your coach adjust next time?",
                   answer_text: "Add a little more rest"
                 }
               ]
             })

    assert review.target_type == "coaching_parameter"
    assert length(review.answers) == 4

    assert {:error, changeset} =
             Feedback.submit_review(user.id, %{
               target_type: "private_coaching_bespoke",
               sentiment: "neutral"
             })

    assert %{target_type: ["is invalid"]} = errors_on(changeset)
  end

  test "application review submission validates concrete target existence" do
    user = TestFixtures.user_fixture()

    assert {:error, :review_target_required} =
             SubmitReview.call(user.id, %{
               target_type: "workout",
               sentiment: "neutral",
               answers: [
                 %{
                   question_key: "ability_match",
                   question_text: "How well did this workout match your current ability today?",
                   answer_text: "No target"
                 }
               ]
             })

    assert {:error, :review_target_not_found} =
             SubmitReview.call(user.id, %{
               target_type: "workout",
               target_id: Ecto.UUID.generate(),
               sentiment: "neutral",
               answers: [
                 %{
                   question_key: "ability_match",
                   question_text: "How well did this workout match your current ability today?",
                   answer_text: "Missing target"
                 }
               ]
             })
  end

  test "application review submission rejects target ids for global review types" do
    user = TestFixtures.user_fixture()

    assert {:error, :review_target_must_be_global} =
             SubmitReview.call(user.id, %{
               target_type: "general",
               target_id: Ecto.UUID.generate(),
               sentiment: "neutral",
               answers: [
                 %{
                   question_key: "general",
                   question_text: "How was the app?",
                   answer_text: "This should not attach to a fake target"
                 }
               ]
             })
  end

  test "application submission writes trusted target snapshots" do
    admin = TestFixtures.admin_fixture()
    user = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin, %{title: "Trusted Snapshot Workout"})

    assert {:ok, execution} =
             Execution.start_execution(user.id, %{
               master_workout_id: workout.id,
               source: :self_selected
             })

    assert {:ok, _completed_execution} = Execution.complete_execution(execution.id, user.id, %{})

    assert {:ok, review} =
             SubmitReview.call(user.id, %{
               target_type: "workout",
               target_id: workout.id,
               target_snapshot: %{"label" => "Forged title"},
               sentiment: "positive",
               rating: 5,
               answers: [
                 %{
                   question_key: "ability_match",
                   question_text: "How well did this workout match your current ability today?",
                   answer_text: "It matched"
                 }
               ]
             })

    assert review.target_snapshot["target_type"] == "workout"
    assert review.target_snapshot["target_id"] == workout.id
    assert review.target_snapshot["label"] == "Trusted Snapshot Workout"
  end

  test "application submission creates an actionable admin review notification" do
    admin = TestFixtures.admin_fixture()
    user = TestFixtures.user_fixture()

    assert {:ok, _review} =
             SubmitReview.call(user.id, %{
               target_type: "general",
               rating: 4,
               sentiment: "positive",
               body: "The new class flow is much clearer."
             })

    assert [notification] = Notifications.list_for_user(admin.id)
    assert notification.type == "review_submitted"
    assert notification.payload["url"] == "/admin/reviews"
  end

  test "application review submission requires completed executions" do
    admin = TestFixtures.admin_fixture()
    user = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin)

    assert {:ok, execution} =
             Execution.start_execution(user.id, %{
               master_workout_id: workout.id,
               source: :self_selected
             })

    params = %{
      target_type: "execution",
      target_id: execution.id,
      sentiment: "neutral",
      answers: [
        %{
          question_key: "ability_match",
          question_text: "How well did this workout match your current ability today?",
          answer_text: "Still doing it"
        }
      ]
    }

    assert {:error, :review_target_not_completed} = SubmitReview.call(user.id, params)

    assert {:ok, _completed_execution} = Execution.complete_execution(execution.id, user.id, %{})
    assert {:ok, review} = SubmitReview.call(user.id, params)
    assert review.target_snapshot["target_type"] == "execution"
  end

  test "application review submission requires attended class slots" do
    admin = TestFixtures.admin_fixture()
    user = TestFixtures.user_fixture()
    workout = TestFixtures.workout_fixture(admin)
    slot = TestFixtures.slot_fixture(workout, %{auto_approve: true})

    assert {:ok, booking} = MilosTraining.Application.SubmitBooking.call(user.id, slot.id)
    assert booking.status == :approved

    params = %{
      target_type: "class_slot",
      target_id: slot.id,
      sentiment: "positive",
      answers: [
        %{
          question_key: "ability_match",
          question_text: "How well did this workout match your current ability today?",
          answer_text: "Good class"
        }
      ]
    }

    assert {:error, :review_target_not_completed} = SubmitReview.call(user.id, params)

    assert {:ok, _attendance} =
             Analytics.record_attendance(%{
               scheduled_class_id: slot.id,
               user_id: user.id,
               status: "attended",
               marked_by_id: admin.id
             })

    assert {:ok, review} = SubmitReview.call(user.id, params)
    assert review.target_snapshot["target_type"] == "class_slot"
  end
end
