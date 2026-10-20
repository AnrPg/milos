defmodule MilosTraining.Application.CommunityGroups do
  @moduledoc """
  Member groups in a gym's club (ADR-143, board 7 Q2–Q3, Q8): the list a
  member browses, proposing one, joining and leaving, what its admins do, and
  what staff decide. Runs on gym routes in the gym's scope. The people a step
  concerns hear about it (proposal → staff, request → the group's admins,
  answers → the person), and the club's realtime topic hears every change.
  """

  alias MilosTraining.Application.{ClubScope, CommunityPeople, RealtimePublisher}
  alias MilosTraining.{Community, Notifications, Organizations}

  @doc "The live groups of the gym's club, with what the member can do in each."
  def list(%{user_id: user_id} = context) do
    with {:ok, club} <- ClubScope.gym_club(context) do
      groups = Community.list_groups(context, club.id)
      reported = MapSet.new(Community.reported_ids(context, user_id, "channel"))
      memberships = memberships(context, user_id, groups)

      {:ok,
       %{
         settings: settings(context, club),
         groups:
           groups
           |> Enum.reject(&MapSet.member?(reported, &1.id))
           |> Enum.map(&present(&1, club, Map.get(memberships, &1.id), user_id))
       }}
    end
  end

  def propose(%{user_id: user_id} = context, params) do
    with {:ok, club} <- ClubScope.gym_club(context),
         {:ok, group} <-
           Community.propose_group(context, club, club.role, %{
             name: params[:name],
             description: params[:description],
             join_policy: params[:join_policy]
           }) do
      if group.status == "pending" do
        notify_staff(:community_group_proposed, context, %{
          club_id: club.id,
          group_id: group.id,
          group_name: group.name,
          person_nickname: nickname(user_id)
        })
      end

      announce(club)
      {:ok, present(group, club, %{source: "auto", role: "admin"}, user_id)}
    end
  end

  @doc "A group with its members; join requests only for those who answer them."
  def show(%{user_id: user_id} = context, group_id) do
    with {:ok, club, group, membership} <- load(context, group_id),
         true <- can_see?(group, club, membership, user_id) || {:error, :not_found} do
      members = Community.group_members(context, group.id)
      manager? = manager?(club, membership)

      shown =
        Enum.filter(members, fn member -> Community.group_member?(member) or manager? end)

      people = CommunityPeople.by_ids(Enum.map(shown, & &1.user_id))

      {:ok,
       Map.put(
         present(with_counts(group, members), club, membership, user_id),
         :members,
         Enum.map(shown, fn member ->
           %{
             person: CommunityPeople.person(people, member.user_id),
             role: member.role,
             status: if(member.source == "requested", do: "requested", else: "member"),
             since: member.since
           }
         end)
       )}
    end
  end

  def join(%{user_id: user_id} = context, group_id) do
    with {:ok, club, group, membership} <- load(context, group_id),
         {:ok, source} <- Community.join_group(context, group, membership) do
      if source == "requested" and not Community.group_member?(membership) do
        notify_admins(context, group, %{person_id: user_id, person_nickname: nickname(user_id)})
      end

      announce(club)
      show(context, group.id)
    end
  end

  def leave(context, group_id, now \\ DateTime.utc_now()) do
    with {:ok, club, group, membership} <- load(context, group_id),
         {:ok, outcome} <- Community.leave_group(context, group, membership, now) do
      announce(club)
      {:ok, %{group_id: group.id, outcome: Atom.to_string(outcome)}}
    end
  end

  def answer_request(context, group_id, user_id, approve?) do
    with {:ok, club, group, membership} <- load(context, group_id),
         :ok <-
           Community.answer_group_request(
             context,
             group,
             actor(club, membership),
             user_id,
             approve?
           ) do
      if approve? do
        Notifications.dispatch_event(:community_group_join_approved, %{
          user_id: user_id,
          organization_id: context.organization_id,
          club_id: group.club_id,
          group_id: group.id,
          group_name: group.name
        })
      end

      announce(club)
      show(context, group.id)
    end
  end

  def set_admin(context, group_id, user_id, admin?) do
    with {:ok, club, group, membership} <- load(context, group_id),
         :ok <-
           Community.set_group_admin(context, group, actor(club, membership), user_id, admin?),
         do: show(context, group.id)
  end

  def remove_member(context, group_id, user_id) do
    with {:ok, club, group, membership} <- load(context, group_id),
         :ok <- Community.remove_group_member(context, group, actor(club, membership), user_id) do
      announce(club)
      show(context, group.id)
    end
  end

  def update(context, group_id, params) do
    with {:ok, club, group, membership} <- load(context, group_id),
         {:ok, _group} <-
           Community.update_group(context, group, actor(club, membership), %{
             name: params[:name] || group.name,
             description: Map.get(params, :description, group.description),
             join_policy: params[:join_policy] || group.join_policy
           }) do
      announce(club)
      show(context, group.id)
    end
  end

  def archive(context, group_id, now \\ DateTime.utc_now()) do
    with {:ok, club, group, membership} <- load(context, group_id),
         {:ok, _group} <- Community.archive_group(context, group, actor(club, membership), now) do
      announce(club)
      {:ok, %{group_id: group.id, outcome: "archived"}}
    end
  end

  # Staff (Κοινότητα › Ομάδες) ---------------------------------------------

  @doc "What staff look after: proposed groups, live ones and archived ones."
  def staff_overview(context) do
    with {:ok, club} <- ClubScope.gym_club(context),
         :ok <- staff(club) do
      pending = Community.list_groups(context, club.id, %{statuses: ["pending"]})
      live = Community.list_groups(context, club.id)
      archived = Community.list_groups(context, club.id, %{archived: true, statuses: ["active"]})
      people = CommunityPeople.by_ids(Enum.map(pending ++ live ++ archived, & &1.created_by_id))

      {:ok,
       %{
         settings: settings(context, club),
         pending: Enum.map(pending, &staff_row(&1, people)),
         live: Enum.map(live, &staff_row(&1, people)),
         archived: Enum.map(archived, &staff_row(&1, people))
       }}
    end
  end

  def decide(%{user_id: _user_id} = context, group_id, decision, now \\ DateTime.utc_now()) do
    with {:ok, club, group, _membership} <- load(context, group_id),
         {:ok, decided} <- Community.decide_group(context, group, club.role, decision, now) do
      type =
        if decided.status == "active",
          do: :community_group_approved,
          else: :community_group_declined

      if group.created_by_id do
        Notifications.dispatch_event(type, %{
          user_id: group.created_by_id,
          organization_id: context.organization_id,
          club_id: group.club_id,
          group_id: group.id,
          group_name: group.name
        })
      end

      announce(club)
      {:ok, staff_row(with_counts(decided, Community.group_members(context, group.id)), %{})}
    end
  end

  def reopen(context, group_id, now \\ DateTime.utc_now()) do
    with {:ok, club, group, _membership} <- load(context, group_id, archived: true),
         {:ok, reopened} <- Community.reopen_group(context, group, club.role, now) do
      announce(club)
      {:ok, staff_row(with_counts(reopened, Community.group_members(context, group.id)), %{})}
    end
  end

  def put_settings(context, params) do
    with {:ok, club} <- ClubScope.gym_club(context),
         :ok <- staff(club),
         {:ok, settings} <-
           Community.put_community_settings(context, %{member_groups: params[:member_groups]}) do
      announce(club)
      {:ok, Map.put(settings, :lifecycle, Community.group_lifecycle())}
    end
  end

  # ------------------------------------------------------------- internals

  @doc false
  def load(%{organization_id: organization_id, user_id: user_id} = context, group_id, opts \\ []) do
    with {:ok, club} <- ClubScope.gym_club(context),
         %{kind: "member_group", club_id: club_id, organization_id: ^organization_id} = group <-
           Community.get_channel(context, group_id) || {:error, :not_found},
         true <- club_id == club.id || {:error, :not_found},
         true <-
           is_nil(group.archived_at) == not Keyword.get(opts, :archived, false) ||
             {:error, :not_found} do
      membership =
        context |> Community.channel_memberships_of(user_id, [group.id]) |> Map.get(group.id)

      {:ok, club, group, membership}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :not_found}
    end
  end

  defp can_see?(%{status: "active"}, _club, _membership, _user_id), do: true

  defp can_see?(group, club, _membership, user_id),
    do: club.role == "staff" or group.created_by_id == user_id

  defp manager?(club, membership) do
    role = if Community.group_member?(membership), do: membership.role
    Community.can_manage_group?(role, club.role)
  end

  defp actor(club, membership), do: %{club_role: club.role, membership: membership}

  defp staff(%{role: "staff"}), do: :ok
  defp staff(_club), do: {:error, :forbidden}

  defp settings(context, club) do
    settings = Community.community_settings(context)

    %{
      member_groups: settings.member_groups,
      can_propose: club.role == "staff" or settings.member_groups != "none",
      needs_approval: club.role != "staff" and settings.member_groups == "approval",
      lifecycle: Community.group_lifecycle()
    }
  end

  defp memberships(context, user_id, groups),
    do: Community.channel_memberships_of(context, user_id, Enum.map(groups, & &1.id))

  defp with_counts(group, members) do
    Map.merge(group, %{
      member_count: Enum.count(members, &Community.group_member?/1),
      request_count: Enum.count(members, &(&1.source == "requested"))
    })
  end

  defp present(group, club, membership, user_id) do
    member? = Community.group_member?(membership)
    admin? = member? and membership.role == "admin"
    manager? = Community.can_manage_group?(if(member?, do: membership.role), club.role)

    %{
      id: group.id,
      club_id: group.club_id,
      name: group.name,
      description: group.description,
      join_policy: group.join_policy,
      status: group.status,
      member_count: Map.get(group, :member_count, if(member?, do: 1, else: 0)),
      request_count: if(manager?, do: Map.get(group, :request_count, 0), else: 0),
      last_post_at: group.last_post_at,
      archive_warned_at: group.archive_warned_at,
      membership:
        cond do
          member? -> "member"
          membership && membership.source == "requested" -> "requested"
          true -> "none"
        end,
      admin: admin?,
      created_by_me: group.created_by_id == user_id,
      can_manage: manager?,
      can_report: group.created_by_id != user_id
    }
  end

  defp staff_row(group, people) do
    %{
      id: group.id,
      name: group.name,
      description: group.description,
      join_policy: group.join_policy,
      status: group.status,
      member_count: Map.get(group, :member_count, 0),
      created_by: group.created_by_id && CommunityPeople.person(people, group.created_by_id),
      inserted_at: group.inserted_at,
      last_post_at: group.last_post_at,
      archive_warned_at: group.archive_warned_at,
      archived_at: group.archived_at
    }
  end

  defp notify_staff(type, %{organization_id: organization_id}, payload) do
    organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.each(fn staff_id ->
      Notifications.dispatch_event(
        type,
        Map.merge(payload, %{user_id: staff_id, organization_id: organization_id})
      )
    end)
  end

  defp notify_admins(%{organization_id: organization_id} = context, group, payload) do
    context
    |> Community.group_members(group.id)
    |> Enum.filter(&(Community.group_member?(&1) and &1.role == "admin"))
    |> Enum.each(fn admin ->
      Notifications.dispatch_event(
        :community_group_join_requested,
        Map.merge(payload, %{
          user_id: admin.user_id,
          organization_id: organization_id,
          club_id: group.club_id,
          group_id: group.id,
          group_name: group.name
        })
      )
    end)
  end

  defp nickname(user_id),
    do: CommunityPeople.by_ids([user_id]) |> CommunityPeople.person(user_id) |> Map.get(:nickname)

  defp announce(club),
    do:
      RealtimePublisher.broadcast("community:club:#{club.id}", "channels_changed", %{
        club_id: club.id
      })
end
