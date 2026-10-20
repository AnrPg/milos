defmodule MilosTraining.Application.OpenClubs do
  @moduledoc """
  Open clubs (ADR-143, board 7 Q6–Q7): «Βρες» lists them with the groups of
  the member's gyms; anyone signed in can open one and join it (straight
  away, or after staff approve). Staff of the gym that runs a club create,
  edit and archive it and answer join requests from «Κοινότητα». Joins and
  answers run in the scope of the gym that runs the club.
  """

  alias MilosTraining.Application.{
    ClubScope,
    CommunityGroups,
    CommunityPeople,
    MediaUrls,
    RealtimePublisher,
    ReleaseMedia
  }

  alias MilosTraining.{Community, Media, Notifications, Organizations}

  # Member side (personal routes) --------------------------------------------

  @doc """
  «Βρες»: the groups of the member's gyms they are not in, then the open
  clubs of boxes they belong to or follow (board 7 Q7; places nearby join in
  M6).
  """
  def discover(%{user_id: user_id} = context, params) do
    with {:ok, clubs} <- ClubScope.call(context) do
      query = params[:q]

      organization_ids =
        Enum.uniq(
          Enum.map(clubs, & &1.organization_id) ++
            Community.followed_ids(context, user_id, "organization")
        )

      open =
        Community.list_open_clubs(context, %{
          organization_ids: organization_ids,
          query: query,
          limit: 50
        })

      {:ok,
       %{
         clubs: present_clubs(context, open, clubs),
         groups: discover_groups(context, clubs, query, user_id)
       }}
    end
  end

  @doc "An open club's face, for members and for someone deciding to join."
  def show(context, club_id) do
    with {:ok, club} <- fetch(context, club_id),
         {:ok, clubs} <- ClubScope.call(context) do
      [shown] = present_clubs(context, [club], clubs)
      {:ok, shown}
    end
  end

  def join(%{user_id: user_id} = context, club_id) do
    with {:ok, club} <- fetch(context, club_id),
         {:ok, status} <- Community.join_open_club(ClubScope.write_context(club, context), club) do
      if status == "pending" do
        notify_staff(club, %{
          person_id: user_id,
          person_nickname: nickname(user_id)
        })
      end

      announce(club)
      show(context, club.id)
    end
  end

  def leave(context, club_id) do
    with {:ok, club} <- fetch(context, club_id),
         :ok <- Community.leave_open_club(ClubScope.write_context(club, context), club) do
      announce(club)
      show(context, club.id)
    end
  end

  def set_notify_level(%{user_id: user_id} = context, club_id, level) do
    with {:ok, club} <- fetch(context, club_id),
         true <- level in Community.notify_level_options() || {:error, :invalid_notify_level},
         write = ClubScope.write_context(club, context),
         %{status: "active"} <-
           Community.club_memberships(write, club.id, "active")
           |> Enum.find(&(&1.user_id == user_id)) || {:error, :not_found},
         :ok <- Community.set_open_club_notify_level(write, club, level) do
      {:ok, level}
    end
  end

  # Staff side (gym routes, Κοινότητα › Ανοιχτά clubs) -----------------------

  def staff_list(context) do
    with {:ok, _club} <- staff_club(context) do
      clubs =
        Community.list_open_clubs(context, %{
          organization_ids: [context.organization_id],
          limit: 200
        })

      counts = Community.open_club_member_counts(context, Enum.map(clubs, & &1.id))

      urls = covers(context, clubs)

      {:ok,
       Enum.map(clubs, fn club ->
         pending = Community.club_memberships(context, club.id, "pending")

         club
         |> base(urls)
         |> Map.merge(%{
           member_count: Map.get(counts, club.id, 0),
           request_count: length(pending)
         })
       end)}
    end
  end

  def create(context, params) do
    attrs = editable(params)

    with {:ok, gym_club} <- staff_club(context),
         :ok <- cover_ready(context, attrs),
         {:ok, club} <- Community.create_open_club(context, gym_club.role, attrs) do
      settle_cover(context, nil, club.cover_media_id)
      {:ok, Map.merge(base(club, covers(context, [club])), %{member_count: 0, request_count: 0})}
    end
  end

  def update(context, club_id, params) do
    attrs = editable(params)

    with {:ok, gym_club} <- staff_club(context),
         {:ok, club} <- own_club(context, club_id),
         :ok <- cover_ready(context, attrs),
         {:ok, updated} <- Community.update_open_club(context, club, gym_club.role, attrs) do
      settle_cover(context, club.cover_media_id, updated.cover_media_id)
      announce(club)
      staff_show(context, club.id)
    end
  end

  @doc "A box's open clubs for its public page (board 7 Q6), read in the gym's own scope."
  def for_box(%{organization_id: organization_id} = context) do
    clubs = Community.list_open_clubs(context, %{organization_ids: [organization_id], limit: 50})
    counts = Community.open_club_member_counts(context, Enum.map(clubs, & &1.id))
    urls = covers(context, clubs)

    Enum.map(clubs, fn club ->
      club |> base(urls) |> Map.put(:member_count, Map.get(counts, club.id, 0))
    end)
  end

  def archive(context, club_id, now \\ DateTime.utc_now()) do
    with {:ok, gym_club} <- staff_club(context),
         {:ok, club} <- own_club(context, club_id),
         {:ok, _club} <- Community.archive_open_club(context, club, gym_club.role, now) do
      announce(club)
      {:ok, %{club_id: club.id, archived: true}}
    end
  end

  @doc "A club of the gym with its members and waiting requests."
  def staff_show(context, club_id) do
    with {:ok, _gym_club} <- staff_club(context),
         {:ok, club} <- own_club(context, club_id) do
      rows = Community.club_memberships(context, club.id)
      people = CommunityPeople.by_ids(Enum.map(rows, & &1.user_id))

      {members, requests} = Enum.split_with(rows, &(&1.status == "active"))

      row = fn membership ->
        %{
          person: CommunityPeople.person(people, membership.user_id),
          since: membership.inserted_at
        }
      end

      {:ok,
       club
       |> base(covers(context, [club]))
       |> Map.merge(%{
         member_count: length(members),
         request_count: length(requests),
         members: Enum.map(members, row),
         requests: Enum.map(requests, row)
       })}
    end
  end

  def answer_request(context, club_id, user_id, approve?) do
    with {:ok, gym_club} <- staff_club(context),
         {:ok, club} <- own_club(context, club_id),
         {:ok, _answer} <-
           answered(
             Community.answer_club_request(context, club, gym_club.role, user_id, approve?)
           ) do
      if approve? do
        Notifications.dispatch_event(:community_club_join_approved, %{
          user_id: user_id,
          organization_id: club.organization_id,
          club_id: club.id,
          club_name: club.name
        })
      end

      announce(club)
      staff_show(context, club.id)
    end
  end

  def remove_member(context, club_id, user_id) do
    with {:ok, gym_club} <- staff_club(context),
         {:ok, club} <- own_club(context, club_id),
         :ok <- Community.remove_club_member(context, club, gym_club.role, user_id) do
      announce(club)
      staff_show(context, club.id)
    end
  end

  # ------------------------------------------------------------- internals

  defp fetch(context, club_id) do
    case Community.list_clubs_by_ids(context, [club_id]) do
      [%{kind: "open"} = club] -> {:ok, club}
      _none -> {:error, :not_found}
    end
  end

  defp own_club(%{organization_id: organization_id} = context, club_id) do
    case fetch(context, club_id) do
      {:ok, %{organization_id: ^organization_id} = club} -> {:ok, club}
      _other -> {:error, :not_found}
    end
  end

  defp staff_club(context) do
    with {:ok, club} <- ClubScope.gym_club(context) do
      if club.role == "staff", do: {:ok, club}, else: {:error, :forbidden}
    end
  end

  defp answered(:ok), do: {:ok, :done}
  defp answered({:ok, _membership}), do: {:ok, :done}
  defp answered(error), do: error

  defp editable(params) do
    [:name, :description, :join_policy, :cover_media_id]
    |> Enum.filter(&Map.has_key?(params, &1))
    |> Map.new(&{&1, Map.get(params, &1)})
  end

  defp base(club, cover_urls) do
    %{
      id: club.id,
      organization_id: club.organization_id,
      name: club.name,
      description: club.description,
      join_policy: club.join_policy,
      cover_media_id: club.cover_media_id,
      cover_url: club.cover_media_id && Map.get(cover_urls, club.cover_media_id)
    }
  end

  # Covers are the gym's public box photos (ADR-148), read in each gym's scope.
  defp covers(_context, clubs) do
    clubs
    |> Enum.reject(&is_nil(&1.cover_media_id))
    |> Enum.group_by(& &1.organization_id, & &1.cover_media_id)
    |> Enum.flat_map(fn {organization_id, ids} ->
      gym = %{organization_id: organization_id}
      gym |> Media.list(:tenant, ids) |> then(&MediaUrls.present_all(gym, &1))
    end)
    |> Map.new(&{&1.id, &1.url})
  end

  defp cover_ready(context, %{cover_media_id: id}) when is_binary(id) do
    case Media.fetch_ready(context, "box_photo", [id]) do
      {:ok, _media} -> :ok
      error -> error
    end
  end

  defp cover_ready(_context, _attrs), do: :ok

  # The new cover is in use; the one it replaced is released.
  defp settle_cover(_context, same, same), do: :ok

  defp settle_cover(context, before, now) do
    if now, do: :ok = Media.set_attached(context, :tenant, [now], DateTime.utc_now())
    if before, do: ReleaseMedia.call(context, :tenant, [before])
    :ok
  end

  defp present_clubs(_context, [], _scope), do: []

  defp present_clubs(%{user_id: user_id} = context, clubs, scope) do
    counts = Community.open_club_member_counts(context, Enum.map(clubs, & &1.id))
    urls = covers(context, clubs)

    statuses =
      context |> Community.open_club_memberships_of(user_id) |> Map.new(&{&1.club_id, &1.status})

    in_scope = Map.new(scope, &{&1.id, &1})
    member_of = Map.new(scope, &{&1.organization_id, &1})

    boxes =
      clubs
      |> Enum.map(& &1.organization_id)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(member_of, &1))
      |> case do
        [] -> %{}
        ids -> ids |> Organizations.public_boxes() |> Map.new(&{&1.organization_id, &1})
      end

    Enum.map(clubs, fn club ->
      scoped = Map.get(in_scope, club.id)
      box = Map.get(boxes, club.organization_id)
      gym = Enum.find(scope, &(&1.organization_id == club.organization_id and &1.kind == "gym"))

      club
      |> base(urls)
      |> Map.merge(%{
        member_count: Map.get(counts, club.id, 0),
        membership:
          case Map.get(statuses, club.id) do
            "active" -> "member"
            "pending" -> "requested"
            nil -> "none"
          end,
        role: scoped && scoped.role,
        box: %{
          name: (gym && gym.organization_name) || (box && box.name),
          slug: (gym && gym.organization_slug) || (box && box.slug),
          logo_url: (gym && gym.logo_url) || (box && box.logo_url)
        },
        channels:
          if(scoped, do: Enum.map(scoped.channels, &Map.take(&1, [:id, :kind, :name])), else: [])
      })
    end)
  end

  defp discover_groups(context, clubs, query, _user_id) do
    clubs
    |> Enum.filter(&(&1.kind == "gym"))
    |> Enum.flat_map(fn club ->
      write = ClubScope.write_context(club, context)

      case CommunityGroups.list(write) do
        {:ok, %{groups: groups}} ->
          groups
          |> Enum.filter(&(&1.membership != "member"))
          |> Enum.filter(&matches?(&1.name, query))
          |> Enum.map(
            &Map.put(&1, :club, %{
              id: club.id,
              name: club.name,
              organization_slug: club.organization_slug
            })
          )

        _error ->
          []
      end
    end)
  end

  defp matches?(_name, query) when query in [nil, ""], do: true

  defp matches?(name, query),
    do: String.contains?(String.downcase(name || ""), String.downcase(query))

  defp notify_staff(club, payload) do
    club.organization_id
    |> Organizations.list_staff_user_ids()
    |> Enum.each(fn staff_id ->
      Notifications.dispatch_event(
        :community_club_join_requested,
        Map.merge(payload, %{
          user_id: staff_id,
          organization_id: club.organization_id,
          club_id: club.id,
          club_name: club.name
        })
      )
    end)
  end

  defp nickname(user_id),
    do:
      [user_id]
      |> CommunityPeople.by_ids()
      |> CommunityPeople.person(user_id)
      |> Map.get(:nickname)

  defp announce(club),
    do:
      RealtimePublisher.broadcast("community:club:#{club.id}", "channels_changed", %{
        club_id: club.id
      })
end
