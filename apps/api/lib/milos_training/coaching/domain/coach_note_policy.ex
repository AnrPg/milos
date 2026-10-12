defmodule MilosTraining.Coaching.Domain.CoachNotePolicy do
  @moduledoc """
  Who reads a coach's private notes (ADR-101): the author; owners always;
  admins only while the author lets admins read them. Nobody else, head
  coaches included. Reads by anyone but the author are logged, and the coach
  is told when an admin read a note.
  """

  @doc "`reader_roles` in the gym; `author_allows_admins` is the author's setting."
  def readable?(note, reader_id, reader_roles, author_allows_admins) do
    cond do
      note.coach_user_id == reader_id -> true
      :owner in reader_roles -> true
      :admin in reader_roles -> author_allows_admins == true
      true -> false
    end
  end

  def logged?(note, reader_id), do: note.coach_user_id != reader_id

  @doc "Owners read without notifying the coach; admins notify."
  def notify_author?(note, reader_id, reader_roles),
    do: logged?(note, reader_id) and :owner not in reader_roles

  def can_edit?(note, user_id), do: note.coach_user_id == user_id
end
