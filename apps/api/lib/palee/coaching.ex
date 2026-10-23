defmodule Palee.Coaching do
  alias Palee.Coaching.Commands.RefreshAggregates
  alias Palee.Coaching.Queries.GetAggregates
  alias Palee.Coaching.{CoachingStore, FormReviewStore, NoteStore, RelationshipStore}

  defdelegate get_aggregates(), to: GetAggregates, as: :call
  defdelegate get_aggregates(context), to: GetAggregates, as: :call

  @doc """
  The coaching aggregate computed live for some people only (ADR-186 §7: a
  branch filter); `nil` reads the business-wide view.
  """
  def get_aggregates(context, nil), do: get_aggregates(context)

  def get_aggregates(context, user_ids) when is_list(user_ids),
    do: CoachingStore.with_tenant_context(context, fn -> CoachingStore.get_aggregates_for_users(user_ids) end)
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

  # Private coach notes (ADR-101).
  def create_note(context, attrs), do: NoteStore.create(context, attrs)
  def note_subject_kinds, do: Palee.Coaching.Note.subject_kinds()
  def get_note(context, id), do: NoteStore.get(context, id)
  def update_note(context, id, attrs), do: NoteStore.update(context, id, attrs)
  def delete_note(context, id), do: NoteStore.delete(context, id)
  def list_client_notes(context, client_id), do: NoteStore.list_for_client(context, client_id)

  def record_note_reads(context, note_ids, reader_id, at),
    do: NoteStore.record_reads(context, note_ids, reader_id, at)

  def list_note_reads(context, coach_id), do: NoteStore.list_reads(context, coach_id)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: Palee.Coaching.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
