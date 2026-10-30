defmodule Palee.Application.ListMessagingThreads do
  @moduledoc """
  The gym's threads a reader takes part in. ADR-282: someone in the box's
  inbox reads every box thread (they get a row on the way), and box threads
  they may no longer read drop out. The person's own thread with the box
  is read from `BoxConversation` (Μηνύματα › Box), so it is left out here.
  Box threads carry `box_person` (newcomer, blocked) for the inbox rows.
  """

  alias Palee.Application.BoxInbox
  alias Palee.{Identity, Messaging}

  def call(context, user_id, context_type) do
    lens = BoxInbox.lens(context)
    BoxInbox.join_inbox(lens, user_id)

    threads =
      user_id
      |> Messaging.list_threads_for_user(context_type)
      |> Enum.filter(&BoxInbox.visible?(&1, user_id, lens))
      |> Enum.reject(&(&1.context_type == :box and &1.context_id == user_id))

    nicknames =
      threads
      |> Enum.flat_map(fn thread -> Enum.map(thread.participants || [], & &1.user_id) end)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    flags = box_flags(context, threads)

    Enum.map(threads, fn thread ->
      participants =
        Enum.map(thread.participants || [], fn participant ->
          participant
          |> Map.from_struct()
          |> Map.put(:nickname, Map.get(nicknames, participant.user_id))
        end)

      thread
      |> Map.put(:participants, participants)
      |> Map.put(:box_person, if(thread.context_type == :box, do: flags[thread.context_id]))
    end)
  end

  defp box_flags(%{organization_id: organization_id}, threads) when is_binary(organization_id) do
    person_ids = for %{context_type: :box, context_id: id} <- threads, do: id
    BoxInbox.flags(organization_id, person_ids)
  end

  defp box_flags(_context, _threads), do: %{}
end
