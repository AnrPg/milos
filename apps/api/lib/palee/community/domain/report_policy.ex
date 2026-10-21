defmodule Palee.Community.Domain.ReportPolicy do
  @moduledoc """
  Reporting in a club and what staff do about it (ADR-143, board 7 Q4–Q5).
  Pure.

  Anyone who can see an item can report it once; the item then disappears
  for them. Staff act on the item, which closes every open report on it at
  once: hide or delete a post or comment, archive a group, or decide that
  nothing is needed.
  """

  alias Palee.Community.Report

  @actions %{
    "hide" => {"actioned", "hidden"},
    "delete" => {"actioned", "deleted"},
    "archive" => {"actioned", "archived"},
    "dismiss" => {"dismissed", "none"}
  }

  # ADR-169: hiding a Partners profile suspends it in that club.
  @targets_by_action %{
    "hide" => ~w(post comment partner),
    "delete" => ~w(post comment),
    "archive" => ~w(channel),
    "dismiss" => ~w(post comment channel partner)
  }

  def reasons, do: Report.reasons()
  def target_types, do: Report.target_types()
  def actions, do: Map.keys(@actions)

  @doc "Whether staff may take `action` on a target of this type."
  def action_applies?(action, target_type),
    do: target_type in Map.get(@targets_by_action, action, [])

  @doc "The status and resolution an action closes reports with."
  def resolve(action, target_type) do
    if action_applies?(action, target_type),
      do: {:ok, Map.fetch!(@actions, action)},
      else: {:error, :invalid_action}
  end

  @doc "People don't report their own things."
  def can_report?(%{author_id: author_id}, reporter_id) when author_id == reporter_id,
    do: false

  def can_report?(_target, _reporter_id), do: true
end
