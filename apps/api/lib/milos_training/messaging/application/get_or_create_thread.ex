defmodule MilosTraining.Messaging.Application.GetOrCreateThread do
  alias MilosTraining.Messaging.ThreadStore

  def call(%{context_type: :direct, actor_id: actor_id, participant_id: participant_id}) do
    direct_key = direct_key(actor_id, participant_id)

    ThreadStore.get_or_create_thread(
      %{context_type: :direct, created_by_id: actor_id, direct_key: direct_key},
      [actor_id, participant_id]
    )
  end

  def call(%{context_type: context_type, context_id: context_id, actor_id: actor_id} = params)
      when context_type in [:assignment, :class_slot] do
    participant_ids = Map.get(params, :participants, [actor_id])

    ThreadStore.get_or_create_thread(
      %{context_type: context_type, context_id: context_id, created_by_id: actor_id},
      participant_ids
    )
  end

  defp direct_key(actor_id, participant_id),
    do: [actor_id, participant_id] |> Enum.sort() |> Enum.join(":")
end
