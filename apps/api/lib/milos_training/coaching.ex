defmodule MilosTraining.Coaching do
  alias MilosTraining.Coaching.Commands.RefreshAggregates
  alias MilosTraining.Coaching.Queries.GetAggregates
  alias MilosTraining.Coaching.{CoachingStore, FormReviewStore, RelationshipStore}

  defdelegate get_aggregates(), to: GetAggregates, as: :call
  defdelegate get_aggregates(context), to: GetAggregates, as: :call
  defdelegate refresh_aggregates(), to: RefreshAggregates, as: :call
  defdelegate with_tenant_context(context, fun), to: CoachingStore

  # Form reviews and overdue-reply alerts (ADR-098).
  def create_form_review(context, attrs), do: FormReviewStore.create_review(context, attrs)
  def get_form_review(context, id), do: FormReviewStore.get_review(context, id)

  def list_form_reviews(context, filters \\ %{}),
    do: FormReviewStore.list_reviews(context, filters)

  def complete_form_review(context, id, attrs), do: FormReviewStore.review(context, id, attrs)
  def withdraw_form_review(context, id), do: FormReviewStore.withdraw(context, id)

  def alerted_message_ids(context, message_ids),
    do: FormReviewStore.alerted_message_ids(context, message_ids)

  def record_reply_alert(context, attrs), do: FormReviewStore.record_alert(context, attrs)

  # Coaching relationships (ADR-100).
  def start_relationship(context, attrs), do: RelationshipStore.start(context, attrs)

  def end_relationship(context, id, ended_by_id),
    do: RelationshipStore.finish(context, id, ended_by_id)

  def list_relationships(context, filters \\ %{}), do: RelationshipStore.list(context, filters)

  def coaches?(context, coach_id, client_id),
    do:
      is_binary(coach_id) and is_binary(client_id) and
        RelationshipStore.active?(context, coach_id, client_id)

  def list_client_ids(context, coach_id), do: RelationshipStore.client_ids(context, coach_id)
end
