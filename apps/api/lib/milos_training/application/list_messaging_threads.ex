defmodule MilosTraining.Application.ListMessagingThreads do
  alias MilosTraining.{Identity, Messaging}

  def call(user_id, context_type) do
    threads = Messaging.list_threads_for_user(user_id, context_type)

    nicknames =
      threads
      |> Enum.flat_map(fn thread -> Enum.map(thread.participants || [], & &1.user_id) end)
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(threads, fn thread ->
      participants =
        Enum.map(thread.participants || [], fn participant ->
          participant
          |> Map.from_struct()
          |> Map.put(:nickname, Map.get(nicknames, participant.user_id))
        end)

      %{thread | participants: participants}
    end)
  end
end
