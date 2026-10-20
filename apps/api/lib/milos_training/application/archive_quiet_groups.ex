defmodule MilosTraining.Application.ArchiveQuietGroups do
  @moduledoc """
  The daily quiet-group sweep (ADR-143, board 7 Q8): a member group nobody
  posted in for 50 days warns its admins; ten days after that warning, with
  still no post, it is archived. A post clears the warning; staff can reopen
  an archived group from «Κοινότητα».
  """

  alias MilosTraining.Application.RealtimePublisher
  alias MilosTraining.{Community, Notifications, Organizations}

  def call(now \\ DateTime.utc_now()) do
    Organizations.list_active_organizations_for_system()
    |> Enum.each(fn %{organization: organization} ->
      sweep(%{organization_id: organization.id}, now)
    end)
  end

  def sweep(context, now) do
    context
    |> Community.quiet_groups(now)
    |> Enum.each(fn group ->
      case Community.group_quiet_step(group, now) do
        :warn -> warn(context, group, now)
        :archive -> archive(context, group, now)
        :none -> :ok
      end
    end)
  end

  defp warn(%{organization_id: organization_id} = context, group, now) do
    with {:ok, _group} <- Community.mark_group_warned(context, group, now) do
      context
      |> Community.group_members(group.id)
      |> Enum.filter(&(Community.group_member?(&1) and &1.role == "admin"))
      |> Enum.each(fn admin ->
        Notifications.dispatch_event(:community_group_archive_warning, %{
          user_id: admin.user_id,
          organization_id: organization_id,
          club_id: group.club_id,
          group_id: group.id,
          group_name: group.name,
          warned_on: Date.to_iso8601(DateTime.to_date(now))
        })
      end)
    end
  end

  defp archive(context, group, now) do
    with {:ok, _group} <-
           Community.archive_group(context, group, %{club_role: "staff", membership: nil}, now) do
      RealtimePublisher.broadcast("community:club:#{group.club_id}", "channels_changed", %{
        club_id: group.club_id
      })
    end
  end
end
