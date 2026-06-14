defmodule MilosTraining.Messaging.Application.GetOrCreateThread do
  alias MilosTraining.Messaging.ThreadStore

  def call(%{context_type: :direct, actor_id: actor_id, participant_id: participant_id}) do
    case ThreadStore.find_direct_thread(actor_id, participant_id) do
      %{} = thread ->
        {:ok, thread}

      nil ->
        create_direct_thread(actor_id, participant_id)
    end
  end

  def call(%{context_type: context_type, context_id: context_id, actor_id: actor_id} = params)
      when context_type in [:assignment, :class_slot] do
    case ThreadStore.find_context_thread(context_type, context_id) do
      %{} = thread ->
        ensure_participant(thread, actor_id)
        {:ok, thread}

      nil ->
        create_context_thread(params)
    end
  end

  defp create_direct_thread(actor_id, participant_id) do
    with {:ok, thread} <-
           ThreadStore.create_thread(%{context_type: :direct, created_by_id: actor_id}),
         {:ok, _} <- ThreadStore.add_participant(thread.id, actor_id),
         {:ok, _} <- ThreadStore.add_participant(thread.id, participant_id) do
      {:ok, ThreadStore.get_thread_with_participants(thread.id)}
    end
  end

  defp create_context_thread(%{
         context_type: context_type,
         context_id: context_id,
         actor_id: actor_id,
         participants: participant_ids
       }) do
    with {:ok, thread} <-
           ThreadStore.create_thread(%{
             context_type: context_type,
             context_id: context_id,
             created_by_id: actor_id
           }) do
      Enum.each(participant_ids, &ThreadStore.add_participant(thread.id, &1))
      {:ok, ThreadStore.get_thread_with_participants(thread.id)}
    end
  end

  defp create_context_thread(%{
         context_type: context_type,
         context_id: context_id,
         actor_id: actor_id
       }) do
    create_context_thread(%{
      context_type: context_type,
      context_id: context_id,
      actor_id: actor_id,
      participants: [actor_id]
    })
  end

  defp ensure_participant(thread, user_id) do
    ThreadStore.add_participant(thread.id, user_id)
  end
end
