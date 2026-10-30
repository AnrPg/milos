defmodule Palee.Application.BoxConversation do
  @moduledoc """
  ADR-144, board 6 Q6; ADR-282: a person talks to a box. It is the same
  thread staff open with a member (context `box`, about that person), so the
  conversation simply carries on when someone joins, and the box answers it
  from its shared inbox (`BoxInbox`).

  Anyone with an account may write to a published box (ADR-282 Q1); members
  also to their own box when its page is not published. A newcomer («Νέος»)
  sends a few messages until the box answers, and someone the box blocked
  no longer can. Everything runs in the box's scope for that person
  (`%{organization_id: box, user_id: person}`).
  """

  alias Palee.Application.{BoxInbox, PublicBox, SendMessage, TrackMessagingAnalytics}
  alias Palee.{Finance, Identity, Messaging, Organizations, Trials}
  alias Palee.Messaging.Domain.BoxInboxPolicy

  @doc "Opens (or returns) the person's conversation with a box."
  def open(%{id: user_id}, slug) do
    with {:ok, box} <- resolve(slug, user_id),
         context = scope(box, user_id),
         :ok <- may_open(context, user_id),
         {:ok, thread} <-
           Messaging.with_tenant_context(context, fn ->
             with {:ok, thread} <-
                    Messaging.get_or_create_thread(%{
                      context_type: :box,
                      context_id: user_id,
                      actor_id: user_id,
                      participants: [user_id]
                    }),
                  {:ok, _participant} <- Messaging.add_participant(thread.id, user_id, :member) do
               {:ok, thread}
             end
           end) do
      TrackMessagingAnalytics.call({:ok, thread})
      {:ok, present(context, box, thread, user_id)}
    end
  end

  @doc "The conversation and a page of its messages (newest first, `before_id` pages back)."
  def show(%{id: user_id}, slug, params \\ %{}) do
    with {:ok, box, context, thread} <- existing(slug, user_id),
         {:ok, messages} <-
           Messaging.with_tenant_context(context, fn ->
             Messaging.list_messages(thread.id, %{
               actor_id: user_id,
               limit: params[:limit],
               before_id: params[:before_id]
             })
           end) do
      {:ok,
       context
       |> present(box, thread, user_id)
       |> Map.put(:messages, Enum.map(messages, &message/1))}
    end
  end

  @doc """
  The person writes to the box, optionally about a topic; «Προπόνηση»
  brings in their coach (ADR-282).
  """
  def send(%{id: user_id} = user, slug, params) do
    with {:ok, _box, context, thread} <- existing(slug, user_id),
         :ok <- may_write(context, thread, user_id),
         {:ok, message} <-
           Messaging.with_tenant_context(context, fn ->
             with :ok <- BoxInbox.route_topic(thread, params[:topic]) do
               SendMessage.call(user, %{
                 thread_id: thread.id,
                 sender_id: user_id,
                 body: params[:body],
                 topic: params[:topic],
                 client_operation_id: params[:client_operation_id]
               })
             end
           end) do
      {:ok, message(message)}
    end
  end

  def mark_read(%{id: user_id}, slug, message_id) do
    with {:ok, _box, context, thread} <- existing(slug, user_id) do
      Messaging.with_tenant_context(context, fn ->
        Messaging.mark_read(thread.id, user_id, message_id)
      end)
    end
  end

  @doc """
  Every box the person talks to, latest message first: members and
  newcomers alike read these in Μηνύματα › Box (ADR-282).
  """
  def list(%{id: user_id}) do
    organization_ids = Messaging.list_box_conversation_organization_ids(%{user_id: user_id})
    boxes = boxes(organization_ids, user_id)

    organization_ids
    |> Enum.flat_map(fn organization_id ->
      context = %{organization_id: organization_id, user_id: user_id}

      with %{} = box <- boxes[organization_id],
           %{} = thread <- find(context, user_id) do
        [summary(context, box, thread, user_id)]
      else
        _skip -> []
      end
    end)
    |> Enum.sort_by(&(&1.last_message && &1.last_message.inserted_at), &later?/2)
  end

  # -- internals

  defp scope(box, user_id), do: %{organization_id: box.organization_id, user_id: user_id}

  # ADR-282 Q1: anyone may write, unless the box blocked them.
  defp may_open(context, _user_id) do
    if Messaging.with_tenant_context(context, fn -> Messaging.box_blocked?(context.user_id) end),
      do: {:error, :blocked_by_box},
      else: :ok
  end

  defp may_write(context, thread, user_id) do
    with :ok <- may_open(context, user_id) do
      unanswered =
        Messaging.with_tenant_context(context, fn ->
          case Messaging.list_messages(thread.id, %{
                 actor_id: user_id,
                 limit: BoxInboxPolicy.max_unanswered_from_newcomer()
               }) do
            {:ok, messages} -> BoxInboxPolicy.unanswered(thread, messages)
            _error -> 0
          end
        end)

      BoxInboxPolicy.may_write?(BoxInbox.standing(context.organization_id, user_id), unanswered)
    end
  end

  # A published box by its slug, or a box the person belongs to even when
  # its page is not published (they still need to reach it).
  defp resolve(slug, user_id) do
    case PublicBox.resolve(slug) do
      {:ok, box, _scope} -> {:ok, box}
      _not_public -> own_box(slug, user_id)
    end
  end

  defp own_box(slug, user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.find_value({:error, :not_found}, fn %{organization: organization} ->
      if organization.slug == slug, do: {:ok, Organizations.brand_summary(organization.id)}
    end)
  end

  defp boxes(organization_ids, user_id) do
    public =
      organization_ids |> Organizations.public_boxes() |> Map.new(&{&1.organization_id, &1})

    organization_ids
    |> Enum.reject(&Map.has_key?(public, &1))
    |> Enum.filter(&(Organizations.membership_standing(&1, user_id) == :member))
    |> Enum.reduce(public, fn organization_id, boxes ->
      case Organizations.brand_summary(organization_id) do
        %{} = box -> Map.put(boxes, organization_id, box)
        _missing -> boxes
      end
    end)
  end

  defp existing(slug, user_id) do
    with {:ok, box} <- resolve(slug, user_id),
         context = scope(box, user_id),
         %{} = thread <- find(context, user_id) || {:error, :not_found} do
      {:ok, box, context, thread}
    end
  end

  defp find(context, user_id) do
    Messaging.with_tenant_context(context, fn ->
      case Messaging.find_context_thread(:box, user_id) do
        %{participants: participants} = thread ->
          if Enum.any?(participants, &(&1.user_id == user_id)), do: thread

        nil ->
          nil
      end
    end)
  end

  defp present(context, box, thread, user_id) do
    %{
      thread_id: thread.id,
      box: box,
      member: Organizations.membership_standing(box.organization_id, user_id) == :member,
      staff: staff(thread, user_id),
      blocked: Messaging.with_tenant_context(context, fn -> Messaging.box_blocked?(user_id) end),
      last_read_message_id: last_read(thread, user_id),
      conversion_package: conversion_package(context)
    }
  end

  defp summary(context, box, thread, user_id) do
    last =
      Messaging.with_tenant_context(context, fn ->
        case Messaging.list_messages(thread.id, %{actor_id: user_id, limit: 1}) do
          {:ok, [message]} -> message(message)
          _none -> nil
        end
      end)

    read = last_read(thread, user_id)

    %{
      thread_id: thread.id,
      box: box,
      last_message: last,
      unread: not is_nil(last) and last.sender_id != user_id and last.id != read
    }
  end

  defp staff(thread, user_id) do
    thread.participants
    |> Enum.map(& &1.user_id)
    |> Kernel.--([user_id])
    |> Identity.list_by_ids()
    |> Enum.map(&%{id: &1.id, nickname: &1.nickname, avatar_url: Map.get(&1, :avatar_url)})
  end

  defp last_read(thread, user_id) do
    Enum.find_value(thread.participants, &(&1.user_id == user_id && &1.last_read_message_id))
  end

  # Board 6 Q6: the package the owner offers people who join after a trial.
  defp conversion_package(context) do
    with %{conversion_package_id: id} when is_binary(id) <- Trials.policy(context),
         %{active: true} = package <- Finance.get_package(context, id) do
      Map.take(package, [:id, :name, :description, :base_price_cents, :currency, :billing_period])
    else
      _none -> nil
    end
  end

  defp message(message) do
    Map.take(message, [
      :id,
      :thread_id,
      :sender_id,
      :body,
      :message_type,
      :topic,
      :client_operation_id,
      :inserted_at
    ])
  end

  defp later?(nil, _other), do: false
  defp later?(_one, nil), do: true
  defp later?(one, other), do: DateTime.compare(to_dt(one), to_dt(other)) != :lt

  defp to_dt(%DateTime{} = at), do: at
  defp to_dt(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
end
