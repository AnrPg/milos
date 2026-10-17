defmodule MilosTraining.Application.RequestCoachReply do
  @moduledoc """
  Ζητάω απάντηση (ADR-139 §7): the member's question about one journal entry
  goes to their coach as a direct message whose subject is the entry, so it
  lands in the coach's reply queue (ADR-098) and the answer arrives in
  messages. Only an entry recorded in a gym where the member has an active
  coaching relationship can ask (`no_active_coach` otherwise); with several
  coaches the member may name one (`coach_user_id`), else the most recent
  relationship answers.
  """

  alias MilosTraining.Application.SendMessage
  alias MilosTraining.{Coaching, Messaging, Organizations}

  @max_question 5000

  def call(%{user_id: user_id, account: account}, kind, entry, params) do
    with {:ok, question} <- question(params),
         {:ok, organization_id} <- gym(entry),
         {:ok, tenant} <- tenant(account, organization_id),
         {:ok, coach_id} <- coach(tenant, user_id, param(params, "coach_user_id")) do
      Messaging.with_tenant_context(tenant, fn ->
        with {:ok, thread} <-
               Messaging.get_or_create_thread(%{
                 context_type: :direct,
                 actor_id: user_id,
                 participant_id: coach_id
               }) do
          SendMessage.call(account, %{
            thread_id: thread.id,
            sender_id: user_id,
            body: question,
            message_type: :chat,
            subject_kind: kind,
            subject_id: entry.id
          })
        end
      end)
    end
  end

  defp question(params) do
    case param(params, "question") do
      text when is_binary(text) ->
        case String.trim(text) do
          "" -> {:error, :question_required}
          text when byte_size(text) > @max_question -> {:error, :question_too_long}
          text -> {:ok, text}
        end

      _missing ->
        {:error, :question_required}
    end
  end

  defp gym(%{organization_id: organization_id}) when is_binary(organization_id),
    do: {:ok, organization_id}

  defp gym(_entry), do: {:error, :no_gym_for_entry}

  defp tenant(account, organization_id) do
    case Organizations.resolve_tenant_context_by_id(account, organization_id) do
      {:ok, tenant} -> {:ok, tenant}
      {:error, _reason} -> {:error, :no_active_coach}
    end
  end

  defp coach(tenant, user_id, chosen) do
    coach_ids =
      Coaching.with_tenant_context(tenant, fn ->
        tenant
        |> Coaching.list_relationships(%{client_user_id: user_id})
        |> Enum.map(& &1.coach_user_id)
      end)

    cond do
      coach_ids == [] -> {:error, :no_active_coach}
      is_nil(chosen) -> {:ok, hd(coach_ids)}
      chosen in coach_ids -> {:ok, chosen}
      true -> {:error, :no_active_coach}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))
end
