defmodule MilosTraining.Feedback do
  alias MilosTraining.Feedback.Commands.{SubmitReview, UpdateReviewStatus}
  alias MilosTraining.Feedback.Queries.{ListReviews, ListReviewsForUser, ReviewSummary}

  defdelegate submit_review(user_id, params), to: SubmitReview, as: :call
  defdelegate list_reviews_for_user(user_id), to: ListReviewsForUser, as: :call
  defdelegate list_reviews(filters \\ %{}), to: ListReviews, as: :call
  defdelegate update_review_status(review_id, status), to: UpdateReviewStatus, as: :call
  defdelegate review_summary(filters \\ %{}), to: ReviewSummary, as: :call

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Feedback.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
