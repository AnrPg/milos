defmodule Palee.Application.Buddies do
  @moduledoc """
  Εγώ › Buddy για στήριξη (ADR-160 §1, board 15 Q1, Q2, Q7): your buddies
  and the people you support, invitations by id or by a link you share
  yourself, accepting, declining, leaving, what each buddy receives, your
  quiet hours and phone sharing, and the people you can invite.

  Only an invite and an acceptance notify the other person. Declining and
  leaving are quiet: the other side sees it on their page.
  """

  alias Palee.Application.BuddyRealtime
  alias Palee.{Buddies, Identity, Notifications, Wellness}

  @recently_closed_days 30
  @candidate_limit 20

  # Reads.

  @doc "Your buddies, the people you support, invitations waiting for you, your settings."
  def overview(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    _expired = Buddies.expire_stale(context, user_id, now)

    links =
      Buddies.list_links(
        context,
        user_id,
        DateTime.add(now, -@recently_closed_days * 86_400, :second)
      )

    people = people(links, user_id)
    unread = Buddies.unread_counts(context, user_id, Enum.map(links, & &1.id))

    presented =
      Enum.map(links, fn link ->
        link
        |> present(user_id, people, now)
        |> Map.put(:unread_messages, Map.get(unread, link.id, 0))
      end)

    {:ok,
     %{
       buddies: Enum.filter(presented, &(&1.role == "requester")),
       supporting: Enum.filter(presented, &(&1.role == "buddy" and &1.status != "pending")),
       invitations: Enum.filter(presented, &(&1.role == "buddy" and &1.status == "pending")),
       max_buddies: Buddies.max_buddies(),
       invite_days: Buddies.invite_days(),
       settings: Buddies.present_settings(Buddies.settings(context, user_id))
     }}
  end

  @doc "People you can invite: your coaches, follows, and with a term people of a club in common."
  def candidates(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    term = Buddies.search_term(param(params, "q"))
    found = Buddies.candidates(context, term, @candidate_limit)
    users = found |> Enum.map(& &1.user_id) |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

    taken =
      context
      |> Buddies.list_links(user_id, now)
      |> Enum.filter(&Buddies.open_link?(&1, now))
      |> Map.new(&{Buddies.other_party(&1, user_id), Buddies.effective_status(&1, now)})

    {:ok,
     found
     |> Enum.filter(&Map.has_key?(users, &1.user_id))
     |> Enum.map(fn %{user_id: id, relation: relation} ->
       %{person: person(users[id]), relation: relation, link_status: Map.get(taken, id)}
     end)}
  end

  # Invitations.

  @doc "Invite someone you know here by id (coach, club in common, follow)."
  def invite(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    invitee_id = cast_id(param(params, "user_id"))

    with :ok <-
           Buddies.check_eligibility(
             user_id,
             invitee_id,
             invitee_id && Buddies.relation(context, invitee_id)
           ),
         %{} = invitee <- Identity.find_by_id(invitee_id) || {:error, :not_found},
         _expired = Buddies.expire_stale(context, user_id, now),
         {:ok, link} <-
           Buddies.create_link(
             context,
             %{
               user_id: user_id,
               buddy_user_id: invitee.id,
               status: "pending",
               expires_at: Buddies.invite_expires_at(now)
             },
             &Buddies.check_limit(&1, now)
           ) do
      Notifications.dispatch_event(:buddy_invite, %{
        user_id: invitee.id,
        link_id: link.id,
        inviter_id: user_id,
        inviter_nickname: nickname(context.account),
        dedupe_key: "buddy_invite:#{link.id}"
      })

      BuddyRealtime.link_changed(link)

      {:ok, present(link, user_id, %{invitee.id => invitee}, now)}
    end
  end

  @doc """
  An invite link for someone not on Palee yet: shown once, shared by you.
  It works for seven days; whoever signs in and claims it becomes your buddy.
  """
  def create_invite_link(%{user_id: user_id} = context, now \\ DateTime.utc_now()) do
    token = Buddies.generate_invite_token()
    _expired = Buddies.expire_stale(context, user_id, now)

    with {:ok, link} <-
           Buddies.create_link(
             context,
             %{
               user_id: user_id,
               invite_token_hash: Buddies.invite_token_digest(token),
               status: "pending",
               expires_at: Buddies.invite_expires_at(now)
             },
             &Buddies.check_limit(&1, now)
           ) do
      path = Buddies.invite_path(token)

      {:ok,
       %{
         link: present(link, user_id, %{}, now),
         token: token,
         path: path,
         url: public_base_url() <> path,
         expires_at: link.expires_at
       }}
    end
  end

  @doc "The landing page of an invite link: who invited you and whether it still works."
  def invite_preview(token, now \\ DateTime.utc_now()) do
    with {:ok, digest} <- Buddies.decode_invite_token(token),
         %{} = preview <- Buddies.invite_preview(digest, now) || {:error, :not_found} do
      inviter = Identity.find_by_id(preview.inviter_id)

      {:ok,
       %{
         status: preview.status,
         expires_at: preview.expires_at,
         inviter: if(preview.status == "pending" and inviter, do: person(inviter), else: nil)
       }}
    end
  end

  @doc "Claiming an invite link (signed in) makes you that person's buddy."
  def claim_invite(%{user_id: user_id} = context, token, now \\ DateTime.utc_now()) do
    with {:ok, digest} <- Buddies.decode_invite_token(token),
         id when is_binary(id) <-
           Buddies.claim_invite(context, digest, now) || {:error, :buddy_invite_unavailable},
         %{} = link <- Buddies.get_link(context, id) do
      notify_accepted(context, link)
      BuddyRealtime.link_changed(link)
      {:ok, present(link, user_id, people([link], user_id), now)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  # Answers and endings.

  def accept(context, id, now \\ DateTime.utc_now()),
    do: change(context, id, :accept, now)

  def decline(context, id, now \\ DateTime.utc_now()),
    do: change(context, id, :decline, now)

  @doc "Stop: either side, at any time, quietly."
  def leave(context, id, now \\ DateTime.utc_now()),
    do: change(context, id, :leave, now)

  @doc """
  A block ends every open link between two people at once, quietly. For the
  blocking feature to call (there is no block yet in the product).
  """
  def end_for_block(%{user_id: user_id} = context, other_id, now \\ DateTime.utc_now()) do
    context
    |> Buddies.open_links_between(user_id, other_id)
    |> Enum.each(fn link ->
      with {:ok, changes} <-
             Buddies.transition(link, :block, Buddies.link_role(link, user_id), now),
           {:ok, link} <- Buddies.update_link(context, link, changes) do
        BuddyRealtime.link_changed(link)
      end
    end)

    :ok
  end

  defp change(%{user_id: user_id} = context, id, action, now) do
    with %{} = link <- Buddies.get_link(context, id) || {:error, :not_found},
         role when not is_nil(role) <- Buddies.link_role(link, user_id) || {:error, :not_found},
         {:ok, changes} <- Buddies.transition(link, action, role, now),
         {:ok, link} <- Buddies.update_link(context, link, changes) do
      if action == :accept, do: notify_accepted(context, link)
      BuddyRealtime.link_changed(link)
      {:ok, present(link, user_id, people([link], user_id), now)}
    end
  end

  defp notify_accepted(context, link) do
    Notifications.dispatch_event(:buddy_accepted, %{
      user_id: link.user_id,
      link_id: link.id,
      buddy_id: link.buddy_user_id,
      buddy_nickname: nickname(context.account),
      dedupe_key: "buddy_accepted:#{link.id}"
    })
  end

  @doc "What one buddy receives: only what you send, or also the weekly counts summary."
  def update_link(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    with %{} = link <- Buddies.get_link(context, id) || {:error, :not_found},
         true <- Buddies.can_set_summary?(link, user_id, now) || {:error, :forbidden},
         {:ok, flag} <- boolean(param(params, "receives_weekly_summary")),
         {:ok, link} <- Buddies.update_link(context, link, %{receives_weekly_summary: flag}) do
      BuddyRealtime.link_changed(link)
      {:ok, present(link, user_id, people([link], user_id), now)}
    end
  end

  # Settings.

  def settings(%{user_id: user_id} = context),
    do: {:ok, Buddies.present_settings(Buddies.settings(context, user_id))}

  def update_settings(%{user_id: user_id} = context, params) do
    current = Buddies.settings(context, user_id)

    with {:ok, changes} <- Buddies.settings_changes(current, params, &Wellness.valid_zone?/1),
         {:ok, _stored} <- Buddies.put_settings(context, user_id, changes) do
      settings(context)
    end
  end

  # Presentation.

  @doc false
  def present(link, viewer_id, people, now) do
    role = Buddies.link_role(link, viewer_id)
    other = Buddies.other_party(link, viewer_id)

    %{
      id: link.id,
      role: Atom.to_string(role),
      status: Buddies.effective_status(link, now),
      person: other && people |> Map.get(other) |> person(),
      via_link: is_nil(link.buddy_user_id) or not is_nil(link.invite_token_hash),
      receives_weekly_summary: link.receives_weekly_summary,
      expires_at: if(link.status == "pending", do: link.expires_at, else: nil),
      started_at: link.started_at,
      ended_at: link.ended_at,
      ended_by_me: not is_nil(link.ended_by_id) and link.ended_by_id == viewer_id,
      created_at: link.inserted_at
    }
  end

  defp people(links, viewer_id) do
    links
    |> Enum.map(&Buddies.other_party(&1, viewer_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, &1})
  end

  @doc false
  def person(nil), do: nil

  def person(user),
    do: %{id: user.id, nickname: nickname(user), avatar_url: Map.get(user, :avatar_url)}

  @doc false
  def nickname(user), do: Map.get(user, :display_nickname) || Map.get(user, :nickname)

  defp boolean(value) when is_boolean(value), do: {:ok, value}
  defp boolean(_value), do: {:error, :invalid_receives_weekly_summary}

  defp cast_id(id) do
    case Ecto.UUID.cast(id || "") do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp public_base_url,
    do: Application.get_env(:palee, :public_base_url, "") |> String.trim_trailing("/")

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_atom(key)))
end
