defmodule MilosTraining.Application.BoxConversation do
  @moduledoc """
  ADR-144, board 6 Q6: a person talks to a box from its page. It is the same
  thread staff open with a member (context `box`, about that person), so the
  conversation simply carries on once they join and the box's staff answer
  it from their usual inbox.

  Someone who is not a member may open it once they have had (or asked for)
  a trial at the box; members always may. Everything runs in the box's
  scope for that person (`%{organization_id: box, user_id: person}`).
  """

  alias MilosTraining.Application.{PublicBox, SendMessage, TrackMessagingAnalytics}
  alias MilosTraining.{Finance, Identity, Messaging, Organizations, Trials}

  @doc "Opens (or returns) the person's conversation with a published box."
  def open(%{id: user_id}, slug) do
    with {:ok, box, _scope} <- PublicBox.resolve(slug),
         context = scope(box, user_id),
         :ok <- may_open(context, user_id) do
      staff = Organizations.list_staff_user_ids(box.organization_id) -- [user_id]

      with {:ok, thread} <-
             Messaging.with_tenant_context(context, fn ->
               Messaging.get_or_create_thread(%{
                 context_type: :box,
                 context_id: user_id,
                 actor_id: user_id,
                 participants: [user_id | staff]
               })
             end) do
        TrackMessagingAnalytics.call({:ok, thread})
        {:ok, present(context, box, thread, user_id)}
      end
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

  def send(%{id: user_id} = user, slug, params) do
    with {:ok, _box, context, thread} <- existing(slug, user_id),
         {:ok, message} <-
           Messaging.with_tenant_context(context, fn ->
             SendMessage.call(user, %{
               thread_id: thread.id,
               sender_id: user_id,
               body: params[:body],
               client_operation_id: params[:client_operation_id]
             })
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

  @doc "Every box the person talks to this way, latest message first."
  def list(%{id: user_id}) do
    organization_ids = Messaging.list_box_conversation_organization_ids(%{user_id: user_id})
    boxes = organization_ids |> Organizations.public_boxes() |> Map.new(&{&1.organization_id, &1})

    organization_ids
    |> Enum.flat_map(fn organization_id ->
      context = %{organization_id: organization_id, user_id: user_id}

      with %{} = box <- boxes[organization_id],
           # Members read this thread in the gym's own inbox.
           true <- Organizations.membership_standing(organization_id, user_id) != :member,
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

  defp may_open(context, user_id) do
    cond do
      Organizations.membership_standing(context.organization_id, user_id) == :member -> :ok
      Trials.list_requests(context, %{user_id: user_id, limit: 1}) != [] -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp existing(slug, user_id) do
    with {:ok, box, _scope} <- PublicBox.resolve(slug),
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
