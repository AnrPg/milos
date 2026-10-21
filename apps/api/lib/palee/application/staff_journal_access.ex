defmodule Palee.Application.StaffJournalAccess do
  @moduledoc """
  Whether the staff of the context's gym may still read a person's journal
  entries (workouts done, performance) (ADR-162 §7, board 17 Q6). The
  person always reads their own; a gym reads them only while the person is an
  active member. From the day a membership ends the gym keeps its business
  records (bookings, attendance, assignments) but no longer sees what the
  person did.
  """

  alias Palee.Organizations

  def readable?(%{user_id: user_id}, user_id) when is_binary(user_id), do: true

  def readable?(%{organization_id: organization_id}, user_id)
      when is_binary(organization_id) and is_binary(user_id),
      do: Organizations.membership_standing(organization_id, user_id) == :member

  def readable?(_context, _user_id), do: false
end
