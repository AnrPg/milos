defmodule MilosTraining.Journal.JournalStore do
  @moduledoc """
  Facade over the configured Journal adapter. Notes and defaults are
  owner-only under RLS and coach reads are tenant-scoped, so every call runs
  inside a `RepoContext` session (ADR-139).
  """

  @behaviour MilosTraining.Journal.Ports.JournalStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0), do: RepoContext.run(context, fun)

  @impl true
  def list_defaults(user_id), do: adapter().list_defaults(user_id)

  @impl true
  def put_default(user_id, kind, rung), do: adapter().put_default(user_id, kind, rung)

  @impl true
  def create_note(attrs), do: adapter().create_note(attrs)

  @impl true
  def update_note(id, user_id, attrs, lock_version),
    do: adapter().update_note(id, user_id, attrs, lock_version)

  @impl true
  def delete_note(id, user_id, now), do: adapter().delete_note(id, user_id, now)

  @impl true
  def get_note_for_user(id, user_id), do: adapter().get_note_for_user(id, user_id)

  @impl true
  def set_note_visibility(id, user_id, rung), do: adapter().set_note_visibility(id, user_id, rung)

  @impl true
  def move_notes(user_id, from, to), do: adapter().move_notes(user_id, from, to)

  @impl true
  def list_note_items(user_id, bound, limit), do: adapter().list_note_items(user_id, bound, limit)

  @impl true
  def list_coach_visible_notes(user_id, organization_id),
    do: adapter().list_coach_visible_notes(user_id, organization_id)

  @impl true
  def record_coach_reads(rows), do: adapter().record_coach_reads(rows)

  @impl true
  def save_comment(attrs), do: adapter().save_comment(attrs)

  @impl true
  def delete_comment(id, user_id, now), do: adapter().delete_comment(id, user_id, now)

  @impl true
  def list_comments(entry_kind, entry_ids), do: adapter().list_comments(entry_kind, entry_ids)

  @impl true
  def list_changes_since(user_id, since), do: adapter().list_changes_since(user_id, since)

  @impl true
  def entry_owner(entry_kind, entry_id), do: adapter().entry_owner(entry_kind, entry_id)

  @impl true
  def comments_transaction(fun), do: adapter().comments_transaction(fun)

  defp adapter, do: Application.fetch_env!(:milos_training, :journal_store)
end
