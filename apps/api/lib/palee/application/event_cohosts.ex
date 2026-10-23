defmodule Palee.Application.EventCohosts do
  @moduledoc """
  Co-hosting an event (ADR-185 §5), by request and answer.

  * **The host** (its staff with `manage_events`, in its tenant) lists an
    event's co-hosts, invites a published box by its page address, asks
    again after a decline or a removal, and takes a co-host off. A weekly
    event's request covers its later occurrences too.
  * **The invited box** (its staff with `manage_events`, in its own tenant)
    sees its requests and answers them. The rows live in the host's
    tenant; the box reads and answers them only through narrow definer
    functions (ADR-131 §2), never through looser row security.
  * **Accepting** puts the event's card in the box's announcements (so its
    Feed shows it), its members belong to the event's audience, and an
    event open to everyone shows on its box page's Events tab.
  * **After the event** the co-host may send its own trial offer, once, to
    the people who came and are not its members.
  """

  alias Palee.Application.{CommunityEvents, EventNotices, RealtimePublisher}
  alias Palee.{Community, Identity, Organizations, Trials}

  # ------------------------------------------------------------------ host side

  @doc "The event's co-hosts as its host sees them (every status)."
  def list(context, event_id, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         do: {:ok, %{cohosts: rows(context, event, now)}}
  end

  @doc "Invites the box at `slug` to co-host the event (and its later occurrences)."
  def invite(%{user_id: user_id} = context, event_id, slug, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         {:ok, box} <- resolve_box(slug),
         cohosts = Community.list_event_cohosts(context, [event.id]),
         existing = Enum.find(cohosts, &(&1.cohost_organization_id == box.organization_id)),
         :ok <-
           Community.cohost_invite_check(
             event,
             box.organization_id,
             Enum.count(cohosts, &(&1.status in ~w(pending accepted))),
             existing && existing.status,
             now
           ),
         {:ok, request} <- ask(context, event, existing, box.organization_id, user_id) do
      later(context, event, now)
      |> Enum.each(&ask_quietly(context, &1, box.organization_id, user_id, now))

      notify_request(context, event, box, request)
      {:ok, %{cohosts: rows(context, event, now)}}
    end
  end

  @doc "The host takes a co-host off (this occurrence and the later ones)."
  def remove(context, event_id, cohost_id, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context),
         {:ok, event} <- CommunityEvents.fetch_own(context, event_id),
         %{event_id: ^event_id} = cohost <-
           Community.get_event_cohost(context, cohost_id) || {:error, :not_found},
         true <- cohost.status in ~w(pending accepted) || {:error, :not_pending} do
      [event | later(context, event, now)]
      |> Enum.map(& &1.id)
      |> then(&Community.list_event_cohosts(context, &1))
      |> Enum.filter(
        &(&1.cohost_organization_id == cohost.cohost_organization_id and
            &1.status in ~w(pending accepted))
      )
      |> Enum.each(
        &Community.update_event_cohost(context, &1, %{
          status: "removed",
          responded_at: now,
          responded_by_id: context.user_id
        })
      )

      {:ok, %{cohosts: rows(context, event, now)}}
    end
  end

  # ------------------------------------------------------------------ co-host side

  @doc """
  The box's co-host requests, newest first; a weekly event shows once (its
  next occurrence still ahead, else its last).
  """
  def requests(%{organization_id: organization_id} = context, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context) do
      rows =
        context
        |> Community.event_cohost_requests(organization_id)
        |> Enum.group_by(&(&1.series_id || &1.event_id))
        |> Enum.map(fn {_run, occurrences} -> representative(occurrences, now) end)
        |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
        |> present_requests(now)

      {:ok, %{requests: rows}}
    end
  end

  @doc """
  Answers a request: `accepted` or `declined` while pending, `removed` to
  withdraw after accepting. A weekly event's later occurrences follow.
  """
  def respond(
        %{organization_id: organization_id} = context,
        id,
        answer,
        now \\ DateTime.utc_now()
      ) do
    with :ok <- authorize(context),
         %{} = request <- find_request(context, id) || {:error, :not_found},
         :ok <- Community.cohost_answer_check(request.status, answer),
         :ok <- answerable(request, answer, now),
         [_ | _] <- Community.respond_event_cohost(context, request.id, answer, now) || [] do
      box = organization_id |> List.wrap() |> Organizations.public_boxes() |> List.first()
      if answer == "accepted", do: publish_card(context, request)
      notify_answer(request, box, answer, now)
      requests(context, now)
    else
      [] -> {:error, :not_pending}
      error -> error
    end
  end

  @doc """
  The co-host's own trial offer after the event: once, to the people who
  came and are not its members, opening its own trial sheet.
  """
  def trial_offer(%{organization_id: organization_id} = context, id, now \\ DateTime.utc_now()) do
    with :ok <- authorize(context),
         %{} = facts <- Community.cohost_trial_offer_facts(context, id) || {:error, :not_found},
         true <- facts.cohost_organization_id == organization_id || {:error, :not_found},
         :ok <- Community.cohost_trial_offer_check(facts, now),
         %{} = box <-
           organization_id |> List.wrap() |> Organizations.public_boxes() |> List.first() ||
             {:error, :trials_disabled},
         true <- Trials.policy(context).enabled || {:error, :trials_disabled},
         members = Organizations.list_active_membership_user_ids(organization_id),
         [_ | _] = recipients <-
           Community.cohost_trial_offer_recipients(facts.came_user_ids, members),
         true <-
           Community.claim_cohost_trial_offer(context, id, now) ||
             {:error, :trial_offer_already_sent} do
      EventNotices.trial_offer(
        notice_event(facts),
        Enum.map(recipients, &%{user_id: &1}),
        box
      )

      {:ok, %{sent: length(recipients)}}
    else
      [] -> {:error, :nobody_to_offer}
      error -> error
    end
  end

  # ------------------------------------------------------------------ internals

  defp resolve_box(slug) when is_binary(slug) do
    slug = slug |> String.trim() |> String.trim_leading("/") |> String.replace_prefix("b/", "")

    with %{organization_id: id} <- Organizations.public_box_by_slug(slug),
         [box] <- Organizations.public_boxes([id]) do
      {:ok, box}
    else
      _missing -> {:error, :box_not_found}
    end
  end

  defp resolve_box(_slug), do: {:error, :box_not_found}

  defp ask(context, event, nil, cohost_organization_id, user_id),
    do:
      Community.insert_event_cohost(context, %{
        organization_id: event.organization_id,
        event_id: event.id,
        cohost_organization_id: cohost_organization_id,
        invited_by_id: user_id
      })

  defp ask(context, _event, existing, _cohost_organization_id, user_id),
    do:
      Community.update_event_cohost(context, existing, %{
        status: "pending",
        responded_at: nil,
        responded_by_id: nil,
        invited_by_id: user_id
      })

  # A later occurrence that can't take the box (already there, full) is skipped.
  defp ask_quietly(context, event, cohost_organization_id, user_id, now) do
    cohosts = Community.list_event_cohosts(context, [event.id])
    existing = Enum.find(cohosts, &(&1.cohost_organization_id == cohost_organization_id))

    with :ok <-
           Community.cohost_invite_check(
             event,
             cohost_organization_id,
             Enum.count(cohosts, &(&1.status in ~w(pending accepted))),
             existing && existing.status,
             now
           ) do
      ask(context, event, existing, cohost_organization_id, user_id)
    end
  end

  # The run's later, live occurrences.
  defp later(_context, %{series_id: nil}, _now), do: []

  defp later(context, %{series_id: series_id, id: id, starts_at: starts_at}, now) do
    context
    |> Community.list_events(%{series_id: series_id, from: Enum.max([starts_at, now], DateTime)})
    |> Enum.reject(&(&1.id == id or DateTime.compare(&1.starts_at, starts_at) != :gt))
  end

  defp rows(context, event, _now) do
    cohosts = Community.list_event_cohosts(context, [event.id])
    boxes = boxes(Enum.map(cohosts, & &1.cohost_organization_id))

    Enum.map(cohosts, fn cohost ->
      %{
        id: cohost.id,
        status: cohost.status,
        box:
          Map.get(boxes, cohost.cohost_organization_id, unnamed(cohost.cohost_organization_id)),
        invited_at: cohost.inserted_at,
        responded_at: cohost.responded_at
      }
    end)
  end

  defp boxes([]), do: %{}

  defp boxes(ids),
    do:
      ids
      |> Enum.uniq()
      |> Organizations.public_boxes()
      |> Map.new(&{&1.organization_id, face(&1)})

  defp face(box),
    do: %{
      organization_id: box.organization_id,
      slug: box.slug,
      name: box.name,
      logo_url: box.logo_url
    }

  defp unnamed(id), do: %{organization_id: id, slug: nil, name: nil, logo_url: nil}

  defp representative(occurrences, now) do
    sorted = Enum.sort_by(occurrences, & &1.starts_at, DateTime)

    Enum.find(sorted, &Community.cohost_answerable?(&1, now)) ||
      Enum.find(sorted, &(DateTime.compare(&1.ends_at, now) == :gt and &1.status == "accepted")) ||
      List.last(sorted)
  end

  defp present_requests(requests, now) do
    hosts = boxes(Enum.map(requests, & &1.host_organization_id))

    Enum.map(requests, fn request ->
      %{
        id: request.id,
        status: request.status,
        answerable: Community.cohost_answerable?(request, now),
        can_send_trial_offer:
          request.status == "accepted" and
            Community.cohost_trial_offer_check(
              Map.put(request, :status, "accepted"),
              now
            ) == :ok,
        trial_offer_sent_at: request.trial_offer_sent_at,
        invited_at: request.inserted_at,
        responded_at: request.responded_at,
        event: %{
          id: request.event_id,
          title: request.title,
          starts_at: request.starts_at,
          ends_at: request.ends_at,
          time_zone: request.time_zone,
          cancelled_at: request.cancelled_at,
          audience: request.audience,
          weekly: not is_nil(request.series_id)
        },
        host:
          Map.get(hosts, request.host_organization_id) ||
            %{
              organization_id: request.host_organization_id,
              slug: if(request.host_kind == "organiser", do: nil, else: request.host_slug),
              name: request.host_name,
              logo_url: nil
            }
      }
    end)
  end

  defp find_request(%{organization_id: organization_id} = context, id) do
    context
    |> Community.event_cohost_requests(organization_id)
    |> Enum.find(&(&1.id == id))
  end

  # Accepting or declining needs an event still ahead; withdrawing never does.
  defp answerable(_request, "removed", _now), do: :ok

  defp answerable(request, _answer, now) do
    if Community.cohost_answerable?(request, now), do: :ok, else: {:error, :event_started}
  end

  # The event's card in the co-host's announcements: its Feed shows it, and
  # it shows the event only while the box still co-hosts it.
  defp publish_card(%{organization_id: organization_id} = context, request) do
    with %{} = club <-
           context
           |> Community.list_clubs([organization_id])
           |> Enum.find(&(&1.kind == "gym" and is_nil(&1.archived_at))),
         %{channels: channels} <- Community.get_club(context, club.id),
         %{} = channel <- Enum.find(channels, &(&1.kind == "announcements")),
         {:ok, post} <-
           Community.create_post(context, channel, "staff", true, %{
             audience: "club_channel",
             attachment_type: "event",
             attachment_id: request.event_id,
             attachment: %{
               "title" => request.title,
               "starts_at" => DateTime.to_iso8601(request.starts_at),
               "organization_id" => request.host_organization_id,
               "cohost" => true
             }
           }) do
      RealtimePublisher.broadcast("community:club:#{club.id}", "post_created", %{
        post_id: post.id,
        channel_id: channel.id
      })
    end
  end

  defp notify_request(context, event, box, request) do
    host = context.organization_id |> List.wrap() |> Organizations.public_boxes() |> List.first()

    host_name =
      (host && host.name) ||
        case Identity.find_by_id(context.user_id) do
          %{nickname: name} -> name
          _none -> nil
        end

    staff =
      box.organization_id
      |> Organizations.list_staff()
      |> Enum.filter(&runs_events?/1)
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()

    EventNotices.cohost_request(event, staff, host_name, box.organization_id, request.id)
  end

  defp notify_answer(%{invited_by_id: nil}, _box, _answer, _now), do: :ok

  defp notify_answer(request, box, answer, now) do
    EventNotices.cohost_answered(
      notice_event(request),
      request.invited_by_id,
      box && box.name,
      answer,
      request.id,
      now
    )
  end

  defp notice_event(facts),
    do: %{
      id: facts.event_id,
      organization_id: facts.host_organization_id,
      club_id: Map.get(facts, :club_id),
      title: facts.title,
      starts_at: facts.starts_at,
      time_zone: facts.time_zone
    }

  defp runs_events?(%{roles: roles}) when is_list(roles),
    do: Enum.any?(roles, &(to_string(&1) in ~w(owner admin)))

  defp runs_events?(%{role: role}), do: to_string(role) in ~w(owner admin)

  defp authorize(context) do
    if Organizations.can?(context, Community.event_capability()),
      do: :ok,
      else: {:error, :forbidden}
  end
end
