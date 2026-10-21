defmodule MilosTraining.Application.PtSquads do
  @moduledoc """
  PT squads (ADR-168, vision §7.1): a coach's small invite-only channel with
  their own clients, in the gym's club. Runs on gym routes in the gym's
  scope; works the same in a solo coach's organization (ADR-170), where the
  coach is owner and coach.

  The coach starts a squad from «Πελάτες μου», invites active clients (each
  hears about it and accepts or declines), renames, removes and archives.
  A client sees their squads and invitations, answers, and may leave.
  Membership follows coaching: ending a coaching relationship takes the
  client out of that coach's squads (`coaching_ended/3`), and a squad never
  shows to a client whose coaching with its coach is no longer active. The
  club's realtime topic hears every change.
  """

  alias MilosTraining.Application.{ClubScope, CommunityPeople, RealtimePublisher}
  alias MilosTraining.{Coaching, Community, Notifications, Organizations}

  @doc """
  What the person sees: the squads they coach (with archived ones to bring
  back), the squads they are in, the invitations waiting for them, and for a
  coach their active clients to invite.
  """
  def overview(%{organization_id: organization_id, user_id: user_id} = context) do
    with {:ok, club} <- ClubScope.gym_club(context) do
      coach? = coach?(context)
      coach_ids = active_coach_ids(context)

      coached =
        if coach?, do: Community.list_squads(context, club.id, %{coach_id: user_id}), else: []

      archived =
        if coach?,
          do: Community.list_squads(context, club.id, %{coach_id: user_id, archived: true}),
          else: []

      mine =
        context
        |> Community.squad_memberships_of(user_id)
        |> Enum.filter(&(&1.club_id == club.id and &1.coach_id != user_id))
        |> Enum.filter(&(&1.coach_id in coach_ids))

      others =
        case Enum.map(mine, & &1.channel_id) do
          [] -> []
          ids -> Community.list_squads(context, club.id, %{ids: ids})
        end

      by_id = Map.new(mine, &{&1.channel_id, &1})
      {joined, invited} = Enum.split_with(others, &Community.squad_member?(by_id[&1.id]))

      people =
        CommunityPeople.by_ids(
          Enum.map(others, & &1.created_by_id) ++ if(coach?, do: client_ids(context), else: [])
        )

      {:ok,
       %{
         organization_id: organization_id,
         can_create: coach?,
         limits: Community.squad_limits(),
         coached: Enum.map(coached, &summary(&1, "coach", people)),
         archived: Enum.map(archived, &summary(&1, "coach", people)),
         joined: Enum.map(joined, &summary(&1, "member", people)),
         invites: Enum.map(invited, &summary(&1, "invited", people)),
         clients:
           if(coach?,
             do: context |> client_ids() |> Enum.map(&CommunityPeople.person(people, &1)),
             else: []
           )
       }}
    end
  end

  @doc "Starts a squad, inviting `client_ids` with it (checked first: all or none)."
  def create(%{user_id: user_id} = context, params) do
    wanted = List.wrap(params[:client_ids])
    clients = client_ids(context)

    with {:ok, club} <- ClubScope.gym_club(context),
         {:ok, _fresh} <- Community.squad_invitees(wanted, clients, [], user_id),
         {:ok, squad} <-
           Community.create_squad(context, club, roles(context), %{
             name: params[:name],
             description: params[:description]
           }),
         {:ok, fresh} <- Community.invite_to_squad(context, squad, wanted, clients) do
      notify_invited(context, squad, fresh)
      announce(club)
      show(context, squad.id)
    end
  end

  @doc "A squad with its people; its coach also sees who hasn't answered yet."
  def show(context, squad_id) do
    with {:ok, _club, squad, role} <- load(context, squad_id) do
      members = Community.squad_members(context, squad.id)

      shown =
        Enum.filter(members, fn membership ->
          Community.squad_member?(membership) or
            (role == "coach" and Community.squad_invited?(membership))
        end)

      people = CommunityPeople.by_ids([squad.created_by_id | Enum.map(shown, & &1.user_id)])

      squad
      |> Map.merge(%{
        member_count:
          Enum.count(
            members,
            &(Community.squad_member?(&1) and &1.user_id != squad.created_by_id)
          ),
        invite_count: Enum.count(members, &Community.squad_invited?/1)
      })
      |> summary(role, people)
      |> Map.put(
        :members,
        shown
        |> Enum.reject(&(&1.user_id == squad.created_by_id))
        |> Enum.map(fn membership ->
          %{
            person: CommunityPeople.person(people, membership.user_id),
            status: if(Community.squad_member?(membership), do: "member", else: "invited"),
            since: membership.since
          }
        end)
      )
      |> then(&{:ok, &1})
    end
  end

  def invite(context, squad_id, user_ids) do
    with {:ok, club, squad, "coach"} <- load(context, squad_id) |> coach_only(),
         {:ok, fresh} <-
           Community.invite_to_squad(context, squad, List.wrap(user_ids), client_ids(context)) do
      notify_invited(context, squad, fresh)
      announce(club)
      show(context, squad.id)
    end
  end

  def answer(%{user_id: user_id} = context, squad_id, accept?) do
    with {:ok, club, squad, "invited"} <- load(context, squad_id) |> role_only("invited"),
         membership = membership(context, squad, user_id),
         :ok <- Community.answer_squad_invite(context, squad, membership, accept? == true) do
      announce(club)
      if accept?, do: show(context, squad.id), else: {:ok, outcome(squad, "declined")}
    end
  end

  def leave(%{user_id: user_id} = context, squad_id) do
    with {:ok, club, squad, _role} <- load(context, squad_id),
         :ok <- Community.leave_squad(context, squad, membership(context, squad, user_id)) do
      announce(club)
      {:ok, outcome(squad, "left")}
    end
  end

  def remove_member(context, squad_id, user_id) do
    with {:ok, club, squad, "coach"} <- load(context, squad_id) |> coach_only(),
         :ok <- Community.remove_from_squad(context, squad, user_id) do
      announce(club)
      show(context, squad.id)
    end
  end

  def update(context, squad_id, params) do
    with {:ok, club, squad, "coach"} <- load(context, squad_id) |> coach_only(),
         {:ok, _squad} <-
           Community.update_squad(context, squad, %{
             name: params[:name] || squad.name,
             description: Map.get(params, :description, squad.description)
           }) do
      announce(club)
      show(context, squad.id)
    end
  end

  @doc "The coach archives their squad; the gym's managers may too (moderation)."
  def archive(context, squad_id, now \\ DateTime.utc_now()) do
    manager? = Organizations.can?(context, :assign_coaches)

    with {:ok, club, squad} <- load_any(context, squad_id, manager?),
         {:ok, _squad} <- Community.archive_squad(context, squad, manager?, now) do
      announce(club)
      {:ok, outcome(squad, "archived")}
    end
  end

  def reopen(context, squad_id) do
    with {:ok, club, squad} <- load_any(context, squad_id, false, archived: true),
         {:ok, _squad} <- Community.reopen_squad(context, squad) do
      announce(club)
      show(context, squad.id)
    end
  end

  @doc """
  Called when a coaching relationship ends (ADR-100): the client leaves every
  squad of that coach in that gym. Never fails the ending itself.
  """
  def coaching_ended(%{organization_id: _} = context, coach_id, client_id) do
    count = Community.squad_coaching_ended(context, coach_id, client_id)

    if count > 0 do
      case ClubScope.gym_club(%{context | user_id: coach_id}) do
        {:ok, club} -> announce(club)
        _none -> :ok
      end
    end

    :ok
  rescue
    _error -> :ok
  end

  # ------------------------------------------------------------- internals

  # The squad as it applies to the person: `coach`, `member` or `invited`.
  defp load(%{organization_id: organization_id, user_id: user_id} = context, squad_id) do
    with {:ok, club} <- ClubScope.gym_club(context),
         %{kind: "pt_squad", organization_id: ^organization_id, club_id: club_id} = squad <-
           Community.get_channel(context, squad_id) || {:error, :not_found},
         true <- club_id == club.id || {:error, :not_found},
         true <- is_nil(squad.archived_at) || {:error, :not_found} do
      membership = membership(context, squad, user_id)

      cond do
        squad.created_by_id == user_id ->
          {:ok, club, squad, "coach"}

        squad.created_by_id not in active_coach_ids(context) ->
          {:error, :not_found}

        Community.squad_member?(membership) ->
          {:ok, club, squad, "member"}

        Community.squad_invited?(membership) ->
          {:ok, club, squad, "invited"}

        true ->
          {:error, :not_found}
      end
    else
      {:error, _reason} = error -> error
      _other -> {:error, :not_found}
    end
  end

  # For archiving and reopening: the coach (or, to archive, a manager).
  defp load_any(
         %{organization_id: organization_id, user_id: user_id} = context,
         id,
         manager?,
         opts \\ []
       ) do
    archived? = Keyword.get(opts, :archived, false)

    with {:ok, club} <- ClubScope.gym_club(context),
         %{kind: "pt_squad", organization_id: ^organization_id, club_id: club_id} = squad <-
           Community.get_channel(context, id) || {:error, :not_found},
         true <- club_id == club.id || {:error, :not_found},
         true <- is_nil(squad.archived_at) != archived? || {:error, :not_found},
         true <- (squad.created_by_id == user_id or manager?) || {:error, :not_found} do
      {:ok, club, squad}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :not_found}
    end
  end

  defp coach_only({:ok, _club, _squad, "coach"} = loaded), do: loaded
  defp coach_only({:ok, _club, _squad, _role}), do: {:error, :forbidden}
  defp coach_only(error), do: error

  defp role_only({:ok, _club, _squad, role} = loaded, role), do: loaded
  defp role_only({:ok, _club, _squad, _other}, _role), do: {:error, :not_found}
  defp role_only(error, _role), do: error

  defp membership(context, squad, user_id),
    do: context |> Community.channel_memberships_of(user_id, [squad.id]) |> Map.get(squad.id)

  defp roles(%{organization_id: organization_id, user_id: user_id}),
    do: Organizations.member_roles(organization_id, user_id)

  defp coach?(context), do: Community.can_coach_squads?(roles(context))

  defp client_ids(%{user_id: user_id} = context), do: Coaching.list_client_ids(context, user_id)

  defp active_coach_ids(%{user_id: user_id} = context) do
    context
    |> Coaching.list_relationships(%{client_user_id: user_id})
    |> Enum.map(& &1.coach_user_id)
  end

  defp summary(squad, role, people) do
    %{
      id: squad.id,
      club_id: squad.club_id,
      name: squad.name,
      description: squad.description,
      coach: CommunityPeople.person(people, squad.created_by_id),
      member_count: Map.get(squad, :member_count, 0),
      invite_count: if(role == "coach", do: Map.get(squad, :invite_count, 0), else: 0),
      archived_at: squad.archived_at,
      role: role,
      can_manage: role == "coach"
    }
  end

  defp outcome(squad, outcome), do: %{squad_id: squad.id, outcome: outcome}

  defp notify_invited(_context, _squad, []), do: :ok

  defp notify_invited(%{organization_id: organization_id, user_id: coach_id}, squad, user_ids) do
    coach = [coach_id] |> CommunityPeople.by_ids() |> CommunityPeople.person(coach_id)

    Enum.each(user_ids, fn user_id ->
      Notifications.dispatch_event(:community_squad_invited, %{
        user_id: user_id,
        organization_id: organization_id,
        club_id: squad.club_id,
        group_id: squad.id,
        group_name: squad.name,
        person_nickname: coach.nickname
      })
    end)
  end

  defp announce(club),
    do:
      RealtimePublisher.broadcast("community:club:#{club.id}", "channels_changed", %{
        club_id: club.id
      })
end
