defmodule MilosTraining.Journal do
  @moduledoc """
  Journal bounded context (ADR-139): the visibility ladder every journal
  entry carries, the member's default rung per kind, Σημείωση notes and the
  audit of coach reads. Other contexts store their own entries' rung; this
  context owns its rules.
  """

  alias MilosTraining.Journal.Commands.WriteNote
  alias MilosTraining.Journal.Domain.{FeedCursor, FeedItem, Visibility}
  alias MilosTraining.Journal.JournalStore

  def with_context(context, fun) when is_function(fun, 0),
    do: JournalStore.with_context(context, fun)

  # Ladder rules, shared by every context that stores a rung.
  defdelegate visibility_rungs(), to: Visibility, as: :rungs
  defdelegate visibility_kinds(), to: Visibility, as: :kinds
  defdelegate choosable_visibilities(kind), to: Visibility, as: :choosable
  defdelegate visibility_reaches_coach?(rung), to: Visibility, as: :reaches_coach?
  defdelegate validate_visibility_move(kind, rung, in_gym?), to: Visibility, as: :validate_move
  defdelegate validate_visibility_default(kind, rung), to: Visibility, as: :validate_default
  defdelegate visibility_default_kind(kind), to: Visibility, as: :default_kind
  defdelegate bulk_movable_visibility?(rung), to: Visibility, as: :bulk_movable?

  @doc "The rung a new entry of `kind` starts on for this member."
  def initial_visibility(user_id, kind, in_gym?),
    do: Visibility.initial(kind, JournalStore.list_defaults(user_id), in_gym?)

  @doc "Every default kind with the member's choice or the built-in default."
  def visibility_defaults(user_id),
    do: user_id |> JournalStore.list_defaults() |> Visibility.effective_defaults()

  def put_visibility_default(user_id, kind, rung) do
    with :ok <- Visibility.validate_default(kind, rung),
         do: JournalStore.put_default(user_id, kind, rung)
  end

  # Feed paging.
  defdelegate encode_feed_cursor(item), to: FeedCursor, as: :encode
  defdelegate decode_feed_cursor(cursor), to: FeedCursor, as: :decode
  defdelegate feed_bound(kind, cursor), to: FeedCursor, as: :bound
  defdelegate sort_feed(items), to: FeedCursor, as: :sort

  # Notes.
  def write_note(user_id, organization_id, params, now \\ DateTime.utc_now()),
    do: WriteNote.call(user_id, organization_id, params, now)

  def update_note(id, user_id, params, lock_version),
    do: JournalStore.update_note(id, user_id, WriteNote.attrs(params), lock_version)

  def delete_note(id, user_id, now \\ DateTime.utc_now()),
    do: JournalStore.delete_note(id, user_id, now)

  defdelegate get_note_for_user(id, user_id), to: JournalStore
  defdelegate set_note_visibility(id, user_id, rung), to: JournalStore
  defdelegate move_notes(user_id, from, to), to: JournalStore
  defdelegate list_coach_visible_notes(user_id, organization_id), to: JournalStore

  @doc "Live notes, newest first, after `bound`, for the owner or a coach (ADR-139 §9)."
  defdelegate list_note_items(user_id, bound, limit, scope), to: JournalStore

  defdelegate feed_item(kind, entry, occurred_at, opts \\ []), to: FeedItem, as: :build
  defdelegate choosable_visibilities(kind, organization_id), to: FeedItem, as: :choosable

  defdelegate record_coach_reads(rows), to: JournalStore

  # Σχόλια (ADR-140 §1): one store for text on an entry, wherever written.
  defdelegate comment_entry_kinds(), to: MilosTraining.Journal.Comment, as: :entry_kinds
  defdelegate save_comment(attrs), to: JournalStore
  defdelegate delete_comment(id, user_id, now), to: JournalStore
  defdelegate list_comments(entry_kind, entry_ids), to: JournalStore
  defdelegate list_changes_since(user_id, since), to: JournalStore
  defdelegate transaction(fun), to: JournalStore
  defdelegate comment_entry_owner(entry_kind, entry_id), to: JournalStore, as: :entry_owner

  @doc "Comments of each entry, keyed by entry id (entries without any are absent)."
  def comments_by_entry(entry_kind, entry_ids),
    do: entry_kind |> list_comments(entry_ids) |> Enum.group_by(& &1.entry_id)

  # «Τι ένιωσες» (ADR-163): felt muscles and qualities on an entry.
  alias MilosTraining.Journal.{GoalFeedback, GoalFeedbackStore}

  def goal_feedback_entry_kinds, do: GoalFeedback.entry_kinds()

  def goal_feedback_entry(context, entry_kind, entry_id),
    do: GoalFeedbackStore.feedback_entry(context, entry_kind, entry_id)

  def get_goal_feedback(context, entry_kind, entry_id, user_id),
    do: GoalFeedbackStore.get_feedback(context, entry_kind, entry_id, user_id)

  def put_goal_feedback(context, attrs), do: GoalFeedbackStore.put_feedback(context, attrs)

  # ADR-162: one journal across providers.
  alias MilosTraining.Journal.Domain.{CoachAudience, EntrySource, JournalFilter}

  defdelegate parse_filter(params), to: JournalFilter, as: :parse
  defdelegate filter_params(filter), to: JournalFilter, as: :to_params
  defdelegate filter_active_count(filter), to: JournalFilter, as: :active_count
  defdelegate filter_default?(filter), to: JournalFilter, as: :default?
  defdelegate filter_kinds(filter, requested), to: JournalFilter, as: :kinds
  defdelegate filter_query(filter, time_zone), to: JournalFilter, as: :to_query
  defdelegate valid_filter_time_zone?(zone), to: JournalFilter, as: :valid_time_zone?
  defdelegate entry_source(organization_id, device_source, directory), to: EntrySource, as: :label
  defdelegate device_source?(source), to: EntrySource
  defdelegate shareable_kind?(kind), to: CoachAudience, as: :shareable?
  defdelegate audience_member(active_ids, excluded_ids), to: CoachAudience, as: :member
  defdelegate default_audience(member), to: CoachAudience
  defdelegate audience_readers(entry, member, override), to: CoachAudience, as: :readers
  defdelegate audience_reach(entry, member, override), to: CoachAudience, as: :reach
  defdelegate validate_audience(ids, entry, member), to: CoachAudience, as: :validate_override
  defdelegate audience_exclusions_for(ids, member), to: CoachAudience, as: :exclusions_for

  defdelegate list_audience_exclusions(user_id), to: JournalStore
  defdelegate replace_audience_exclusions(user_id, ids), to: JournalStore
  defdelegate entry_audiences(user_id, kind, ids), to: JournalStore
  defdelegate put_entry_audience(user_id, kind, id, ids), to: JournalStore
  defdelegate insert_export(attrs), to: JournalStore
  defdelegate get_export(id, user_id), to: JournalStore
  defdelegate list_exports(user_id), to: JournalStore
  defdelegate finish_export(export, attrs), to: JournalStore

  def tenant_data_policy, do: MilosTraining.Journal.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
