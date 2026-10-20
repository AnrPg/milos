defmodule MilosTraining.Community.Commands.Reports do
  @moduledoc """
  Reports in a club (ADR-143): a member flags an item once; staff act on it,
  which closes every open report on that item.
  """

  alias MilosTraining.Community.CommunityStore
  alias MilosTraining.Community.Domain.ReportPolicy

  @doc """
  Files a report. `target` is what was reported, with `:type`, `:id`,
  `:author_id`, `:club_id` and `:channel_id`. Reporting twice is a no-op.
  """
  def report(%{organization_id: organization_id, user_id: user_id} = context, target, attrs) do
    if ReportPolicy.can_report?(target, user_id) do
      context
      |> CommunityStore.create_report(%{
        organization_id: organization_id,
        club_id: target.club_id,
        channel_id: Map.get(target, :channel_id),
        target_type: target.type,
        target_id: target.id,
        target_author_id: Map.get(target, :author_id),
        reporter_id: user_id,
        reason: Map.get(attrs, :reason),
        note: Map.get(attrs, :note)
      })
      |> case do
        {:ok, report} -> {:ok, report}
        {:error, %Ecto.Changeset{} = changeset} -> already_reported(changeset)
        error -> error
      end
    else
      {:error, :cannot_report_own}
    end
  end

  def list(context, filter), do: CommunityStore.list_reports(context, filter)

  def reported_ids(context, user_id, type),
    do: CommunityStore.reported_ids(context, user_id, type)

  @doc "Closes the open reports on a target after staff took `action` on it."
  def resolve(%{user_id: user_id} = context, target_type, target_id, action) do
    with {:ok, {status, resolution}} <- ReportPolicy.resolve(action, target_type) do
      {:ok,
       CommunityStore.resolve_reports(context, target_type, target_id, %{
         status: status,
         resolution: resolution,
         resolved_by_id: user_id
       })}
    end
  end

  defp already_reported(%{errors: errors} = changeset) do
    if Enum.any?(errors, fn {_field, {message, _meta}} -> message == "already_reported" end),
      do: {:ok, :already_reported},
      else: {:error, changeset}
  end
end
