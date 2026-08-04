defmodule MilosTraining.Feedback.TenantIsolationTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Feedback.FeedbackStore
  alias MilosTraining.Organizations.Organization
  alias MilosTraining.Repo
  alias MilosTraining.TestFixtures

  test "reviews are scoped to their tenant context" do
    user = TestFixtures.user_fixture()
    organization_a = organization_fixture("feedback-a")
    organization_b = organization_fixture("feedback-b")
    context_a = %{organization_id: organization_a.id, user_id: user.id}
    context_b = %{organization_id: organization_b.id, user_id: user.id}

    assert {:ok, review} =
             FeedbackStore.with_tenant_context(context_a, fn ->
               FeedbackStore.submit_review(user.id, %{
                 target_type: "general",
                 sentiment: "positive",
                 visibility: "user_visible",
                 answers: [
                   %{question_key: "q1", question_text: "How was it?", answer_text: "Great"}
                 ]
               })
             end)

    assert [listed] =
             FeedbackStore.with_tenant_context(context_a, fn ->
               FeedbackStore.list_reviews_for_user(user.id)
             end)

    assert listed.id == review.id

    assert FeedbackStore.with_tenant_context(context_b, fn ->
             FeedbackStore.list_reviews_for_user(user.id)
           end) == []
  end

  defp organization_fixture(suffix) do
    {:ok, organization} =
      %Organization{}
      |> Organization.changeset(%{
        name: "Feedback tenant #{suffix}",
        slug: "feedback-tenant-#{suffix}"
      })
      |> Repo.insert()

    organization
  end
end
