defmodule MilosTraining.Journal do
  @moduledoc """
  Journal bounded context (ADR-139): the visibility ladder every journal
  entry carries, the member's default rung per kind, Σημείωση notes and the
  audit of coach reads. Other contexts store their own entries' rung; this
  context owns its rules.
  """

  alias MilosTraining.Journal.Commands.WriteNote
  alias MilosTraining.Journal.Domain.{FeedCursor, Visibility}
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

  @doc "Notes as feed items, newest first, after `bound`."
  def list_note_items(user_id, bound, limit) do
    user_id
    |> JournalStore.list_note_items(bound, limit)
    |> Enum.map(&note_item/1)
  end

  def note_item(note) do
    %{
      kind: "note",
      id: note.id,
      occurred_at: note.written_at,
      occurred_tz: note.written_tz,
      organization_id: note.organization_id,
      journal_visibility: note.journal_visibility,
      note: note
    }
  end

  defdelegate record_coach_reads(rows), to: JournalStore

  # Σχόλια (ADR-140 §1): one store for text on an entry, wherever written.
  defdelegate comment_entry_kinds(), to: MilosTraining.Journal.Comment, as: :entry_kinds
  defdelegate save_comment(attrs), to: JournalStore
  defdelegate delete_comment(id, user_id, now), to: JournalStore
  defdelegate list_comments(entry_kind, entry_ids), to: JournalStore
  defdelegate list_changes_since(user_id, since), to: JournalStore
  defdelegate comments_transaction(fun), to: JournalStore
  defdelegate comment_entry_owner(entry_kind, entry_id), to: JournalStore, as: :entry_owner

  @doc "Comments of each entry, keyed by entry id (entries without any are absent)."
  def comments_by_entry(entry_kind, entry_ids),
    do: entry_kind |> list_comments(entry_ids) |> Enum.group_by(& &1.entry_id)

  def tenant_data_policy, do: MilosTraining.Journal.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
