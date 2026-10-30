defmodule Palee.Application.StaffInjuryAccess do
  @moduledoc """
  Which injury reports a gym's staff member reaches, and the audit of their
  reads (ADR-286).

  `view_health` decides the people: owners, admins and head coaches reach
  every client of the gym, a coach only their own clients (ADR-100). A
  member's own report reaches the gym only while its «Να το δει το box μου»
  switch is on (`shared_with_box`, checked in the database); staff read it,
  the member alone changes it. Every staff read is a row of `injury_access_log`,
  which the member sees in «Κοινοποίηση».
  """

  alias Palee.Application.{AuthorizeClientAccess, TenantStaffRecipients}
  alias Palee.{Organizations, Wellbeing}

  @doc "Narrows list filters to the people the actor may reach."
  def scope_filters(context, filters) do
    case AuthorizeClientAccess.client_ids(context, :view_health) do
      :all -> Map.delete(filters, "user_ids")
      ids when is_list(ids) -> Map.put(filters, "user_ids", ids)
    end
  end

  @doc "Whether the actor may act on this person's injuries."
  def authorize_person(context, user_id),
    do: AuthorizeClientAccess.call(context, :view_health, user_id)

  @doc """
  Loads a report the actor may change: a report of this gym about one of
  the people they reach. Runs inside the caller's tenant session.
  """
  def changeable(context, injury_report_id) do
    with %{} = injury <- Wellbeing.get_box_injury(injury_report_id) || {:error, :not_found},
         :ok <- authorize_person(context, injury.user_id),
         :ok <- box_owned(injury) do
      {:ok, injury}
    end
  end

  @doc "Records one audit row per member whose reports the actor read."
  def log_reads(context, surface, injuries) when is_list(injuries) do
    injuries
    |> Enum.group_by(& &1.user_id, & &1.id)
    |> Enum.each(fn {user_id, ids} ->
      Wellbeing.record_injury_access(%{
        organization_id: context.organization_id,
        user_id: user_id,
        reader_user_id: context.user_id,
        surface: surface,
        injury_ids: ids
      })
    end)
  end

  @doc """
  Staff to tell about a change: the gym's staff for its own report; for a
  member's shared report, the staff of every box where the member is active.
  """
  def staff_user_ids(context, injury) do
    case TenantStaffRecipients.user_ids([context, injury]) do
      [] ->
        if owned_by_member?(injury) and Map.get(injury, :shared_with_box) == true do
          [injury.user_id]
          |> Organizations.list_membership_organization_ids()
          |> Map.get(injury.user_id, [])
          |> Enum.flat_map(&Organizations.list_staff_user_ids/1)
          |> Enum.uniq()
        else
          []
        end

      ids ->
        ids
    end
  end

  @doc "A report the member filed in the app, rather than one the gym keeps."
  def owned_by_member?(%{organization_id: nil}), do: true
  def owned_by_member?(_injury), do: false

  defp box_owned(injury),
    do: if(owned_by_member?(injury), do: {:error, :injury_owned_by_member}, else: :ok)
end
