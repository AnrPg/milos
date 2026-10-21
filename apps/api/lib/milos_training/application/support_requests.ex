defmodule MilosTraining.Application.SupportRequests do
  @moduledoc """
  «Χρειάζομαι στήριξη» (ADR-160 §2, board 15 Q3–Q5, Q7).

  - One tap sends an optional one-line message to every active buddy. It
    can come from Λιγούρα (`source: craving`, through the
    `Ports.SupportRequests` port M11 calls) or from the quick button; either
    way nothing about a craving is stored here or sent.
  - The sender can take it back for five seconds; buddies are told when the
    window closes (a scheduled step). A buddy in quiet hours still gets it,
    silently (inbox, no push), and the sender is told.
  - A few requests an hour at most.
  - A buddy answers with a quick reply (here, walk, call) or their own
    words. The answer is posted into the pair's own buddy conversation
    (account-scoped, whether or not they share a gym) and reaches the
    sender as one push, so they can keep talking. «Πάρε με τηλέφωνο» shows the buddy the sender's phone only if
    the sender shares it with buddies.
  - If nobody answered after ten minutes, the sender gets the calm card
    (breathing, water, a walk, «Στείλε ξανά», help lines as information).
  """

  @behaviour MilosTraining.Application.Ports.SupportRequests

  require Logger

  alias MilosTraining.Application.{BuddyMessages, BuddyRealtime}
  alias MilosTraining.Application.Buddies, as: BuddyPages
  alias MilosTraining.{Buddies, Identity, Localization, Notifications}

  @list_limit 20

  # The port M11's Λιγούρα calls when «Χρειάζομαι στήριξη» is on. Only the
  # craving's id crosses, as an opaque reference. The craving is saved
  # whatever happens here: no buddy yet, or the hourly limit reached, is
  # logged and answered with `:ok`.
  @impl true
  def request(context, %{user_id: user_id} = params) do
    case request_support(
           %{user_id: user_id, account: Map.get(context, :account)},
           %{source: :craving, source_ref: Map.get(params, :craving_id), message: nil},
           Map.get(params, :at) || DateTime.utc_now()
         ) do
      {:ok, _request} ->
        :ok

      {:error, reason} ->
        Logger.info("support request from a craving not sent: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  The buddy facade: asks every active buddy of the person in `context` (a
  user context or a user id) for support. `attrs`: `message` (optional, at
  most 280 characters), `source` (`:craving` or `:quick`), `source_ref`
  (an opaque craving id or nil).
  """
  def request_support(context, attrs, now \\ DateTime.utc_now())

  def request_support(user_id, attrs, now) when is_binary(user_id),
    do: request_support(%{user_id: user_id}, attrs, now)

  def request_support(%{user_id: user_id} = context, attrs, now) do
    with {:ok, message} <- Buddies.normalize_message(param(attrs, "message")),
         {:ok, source} <- Buddies.normalize_source(param(attrs, "source")),
         links = Buddies.active_links_as_requester(context, user_id),
         :ok <- Buddies.check_buddies(links),
         deliveries =
           Enum.map(links, fn link ->
             hours = Buddies.quiet_hours(context, link.buddy_user_id)

             %{
               buddy_user_id: link.buddy_user_id,
               silent: Buddies.quiet_delivery(hours, now).silent
             }
           end),
         {:ok, request} <-
           Buddies.create_request(
             context,
             %{
               user_id: user_id,
               message: message,
               source: source,
               source_ref: cast_id(param(attrs, "source_ref")),
               inserted_at: now
             },
             deliveries,
             &Buddies.check_rate/1,
             Buddies.rate_window_start(now)
           ) do
      scheduler().schedule(user_id, request.id,
        deliver: Buddies.deliver_at(request),
        nudge: Buddies.nudge_at(request)
      )

      BuddyRealtime.request_sent(request)
      show(context, request.id, now)
    end
  end

  @doc "`POST /api/me/support-requests`: the quick button (message optional)."
  def create(context, params, now \\ DateTime.utc_now()),
    do:
      request_support(
        context,
        %{message: param(params, "message"), source: :quick, source_ref: nil},
        now
      )

  @doc "Take a request back within five seconds: nobody is told."
  def undo(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    with %{user_id: ^user_id} = request <-
           Buddies.get_request(context, id) || {:error, :not_found},
         :ok <- Buddies.can_undo?(request, now),
         1 <- Buddies.undo_request(context, request.id, now) do
      BuddyRealtime.request_undone(request)
      show(context, request.id, now)
    else
      %{} -> {:error, :not_found}
      0 -> {:error, :undo_window_passed}
      error -> error
    end
  end

  @doc "Your recent requests (`sent`) or the ones you received (`received`)."
  def list(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    role = if param(params, "role") == "received", do: :received, else: :sent
    requests = Buddies.list_requests(context, user_id, role, @list_limit)
    ids = Enum.map(requests, & &1.id)
    deliveries = context |> Buddies.list_deliveries(ids) |> Enum.group_by(& &1.request_id)
    replies = context |> Buddies.list_replies(ids) |> Enum.group_by(& &1.request_id)
    people = people(requests, Map.values(deliveries) |> List.flatten(), replies)

    {:ok,
     Enum.map(requests, fn request ->
       present(
         request,
         Map.get(deliveries, request.id, []),
         Map.get(replies, request.id, []),
         user_id,
         people,
         now
       )
     end)}
  end

  @doc "One request: for the sender who received and replied, quiet hours, the no-reply card."
  def show(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    with %{} = request <- Buddies.get_request(context, id) || {:error, :not_found},
         deliveries = Buddies.list_deliveries(context, [request.id]),
         true <- visible?(request, deliveries, user_id) || {:error, :not_found} do
      replies = Buddies.list_replies(context, [request.id])
      people = people([request], deliveries, %{request.id => replies})
      {:ok, present(request, deliveries, replies, user_id, people, now)}
    end
  end

  # Row security admits the same; the application checks it too. A buddy
  # sees a request only once it was delivered and while it was not undone.
  defp visible?(%{user_id: user_id}, _deliveries, user_id), do: true

  defp visible?(request, deliveries, user_id),
    do:
      Buddies.can_reply?(request) == :ok and
        Enum.any?(deliveries, &(&1.buddy_user_id == user_id))

  defp own_deliveries(context, request_id, user_id),
    do:
      context
      |> Buddies.list_deliveries([request_id])
      |> Enum.filter(&(&1.buddy_user_id == user_id))

  # Timed steps (SupportRequestJob).

  @doc "Tells the buddies once the undo window passed (idempotent)."
  def deliver(user_id, id, now \\ DateTime.utc_now()) do
    context = %{user_id: user_id}

    with %{user_id: ^user_id} = request <-
           Buddies.get_request(context, id) || {:error, :not_found},
         true <- Buddies.deliverable?(request) || :skip,
         1 <- Buddies.mark_delivered(context, request.id, now) do
      sender = Identity.find_by_id(user_id)
      deliveries = Buddies.list_deliveries(context, [request.id])

      deliveries
      |> Enum.each(fn delivery ->
        Notifications.dispatch_event(:support_request, %{
          user_id: delivery.buddy_user_id,
          request_id: request.id,
          sender_id: user_id,
          sender_nickname: sender && BuddyPages.nickname(sender),
          message: request.message,
          quick_replies: Buddies.quick_replies(),
          silent: delivery.delivered_silently,
          dedupe_key: "support_request:#{request.id}:#{delivery.buddy_user_id}"
        })
      end)

      BuddyRealtime.request_delivered(request, Enum.map(deliveries, & &1.buddy_user_id))
      :ok
    else
      %{} -> {:error, :not_found}
      _skip -> :ok
    end
  end

  @doc "Gives the sender the calm no-reply card, once, if nobody answered (idempotent)."
  def nudge(user_id, id, now \\ DateTime.utc_now()) do
    context = %{user_id: user_id}

    with %{user_id: ^user_id} = request <-
           Buddies.get_request(context, id) || {:error, :not_found},
         replies = Buddies.list_replies(context, [request.id]),
         true <- Buddies.nudge_needed?(request, replies, now) || :skip,
         1 <- Buddies.mark_nudged(context, request.id, now) do
      Notifications.dispatch_event(:support_no_reply_nudge, %{
        user_id: user_id,
        request_id: request.id,
        dedupe_key: "support_no_reply_nudge:#{request.id}"
      })

      BuddyRealtime.request_nudged(request)
      :ok
    else
      %{} -> {:error, :not_found}
      _skip -> :ok
    end
  end

  # Replies.

  @doc """
  A buddy answers: `kind` here|walk|call|text and optional `text`. The
  answer is posted into the pair's buddy conversation (the quick reply's
  text, then the buddy's own words) and the sender is told once.
  """
  def reply(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    with %{} = request <- Buddies.get_request(context, id) || {:error, :not_found},
         true <- request.user_id != user_id || {:error, :not_found},
         :ok <- Buddies.can_reply?(request),
         [_delivery | _] <- own_deliveries(context, request.id, user_id),
         %{} = link <-
           active_link(context, request.user_id, user_id, now) || {:error, :forbidden},
         {:ok, kind, text} <-
           Buddies.validate_reply(param(params, "kind"), param(params, "text")),
         body = Buddies.reply_message_body(kind, quick_reply_text(context, kind), text),
         {:ok, message} <- BuddyMessages.post_reply(context, link, body),
         {:ok, reply} <-
           Buddies.insert_reply(
             context,
             %{
               request_id: request.id,
               user_id: request.user_id,
               buddy_user_id: user_id,
               kind: kind,
               text: text,
               link_id: link.id,
               message_id: message.id
             },
             now
           ) do
      Notifications.dispatch_event(:support_reply, %{
        user_id: request.user_id,
        request_id: request.id,
        reply_id: reply.id,
        link_id: link.id,
        buddy_id: user_id,
        buddy_nickname: BuddyPages.nickname(Map.get(context, :account) || %{}),
        kind: kind,
        text: text,
        dedupe_key: "support_reply:#{reply.id}"
      })

      BuddyRealtime.reply_created(request, reply)

      phone = if kind == "call", do: Buddies.shared_phone(context, request.user_id)

      {:ok,
       %{
         reply: present_reply(reply, people_map([user_id])),
         sender_phone: Buddies.phone_for(kind, phone)
       }}
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  # The requester's active link to this buddy: the conversation the reply
  # goes into.
  defp active_link(context, requester_id, buddy_id, now) do
    context
    |> Buddies.open_links_between(requester_id, buddy_id)
    |> Enum.find(fn link ->
      link.user_id == requester_id and Buddies.effective_status(link, now) == "active"
    end)
  end

  defp quick_reply_text(%{user_id: user_id} = context, kind) do
    account = Map.get(context, :account) || Identity.find_by_id(user_id) || %{}
    locale = Map.get(account, :preferred_locale) || "en"
    Localization.translate(locale, quick_reply_message(kind), %{})
  end

  @doc false
  def quick_reply_message("here"), do: "I'm here"
  def quick_reply_message("walk"), do: "Shall we go for a walk?"
  def quick_reply_message("call"), do: "Call me"
  def quick_reply_message(_kind), do: "I'm here"

  # Presentation.

  defp present(request, deliveries, replies, viewer_id, people, now) do
    if request.user_id == viewer_id,
      do: present_for_sender(request, deliveries, replies, people, now),
      else: present_for_buddy(request, deliveries, replies, viewer_id, people)
  end

  defp present_for_sender(request, deliveries, replies, people, now) do
    %{
      id: request.id,
      role: "sender",
      message: request.message,
      source: request.source,
      created_at: request.inserted_at,
      status: status(request),
      undo_until: Buddies.undo_until(request),
      can_undo: Buddies.can_undo?(request, now) == :ok,
      recipients:
        Enum.map(deliveries, fn delivery ->
          %{
            person: BuddyPages.person(people[delivery.buddy_user_id]),
            quiet_hours: delivery.delivered_silently,
            replied_at: delivery.replied_at
          }
        end),
      quiet_hours:
        for(d <- deliveries, d.delivered_silently, do: BuddyPages.person(people[d.buddy_user_id])),
      replies: Enum.map(replies, &present_reply(&1, people)),
      nudge: Buddies.nudge(request, replies, now)
    }
  end

  # A buddy sees the message and who sent it, never where it came from.
  defp present_for_buddy(request, deliveries, replies, viewer_id, people) do
    mine = Enum.find(deliveries, &(&1.buddy_user_id == viewer_id))

    %{
      id: request.id,
      role: "buddy",
      message: request.message,
      created_at: request.inserted_at,
      status: status(request),
      sender: BuddyPages.person(people[request.user_id]),
      delivered_silently: (mine && mine.delivered_silently) || false,
      quick_replies: Buddies.quick_replies(),
      replies:
        replies
        |> Enum.filter(&(&1.buddy_user_id == viewer_id))
        |> Enum.map(&present_reply(&1, people))
    }
  end

  defp present_reply(reply, people) do
    %{
      id: reply.id,
      kind: reply.kind,
      text: reply.text,
      person: BuddyPages.person(people[reply.buddy_user_id]),
      created_at: reply.inserted_at,
      conversation:
        if(reply.link_id, do: %{link_id: reply.link_id, message_id: reply.message_id}, else: nil)
    }
  end

  defp status(%{undone_at: at}) when not is_nil(at), do: "undone"
  defp status(%{delivered_at: nil}), do: "sending"
  defp status(_request), do: "delivered"

  defp people(requests, deliveries, replies) do
    ids =
      Enum.map(requests, & &1.user_id) ++
        Enum.map(deliveries, & &1.buddy_user_id) ++
        (replies |> Map.values() |> List.flatten() |> Enum.map(& &1.buddy_user_id))

    people_map(ids)
  end

  defp people_map(ids), do: ids |> Enum.uniq() |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

  defp scheduler, do: Application.fetch_env!(:milos_training, :support_scheduler)

  defp cast_id(nil), do: nil

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, String.to_atom(key)))
end
