defmodule Palee.Application.BoxInbox do
  @moduledoc """
  ADR-282: the box's side of the threads people have with it.

  The box answers from one shared inbox: whoever may message for the box
  (`message_from_box`) reads every thread, worked out from the roles each
  time, so a new hire sees the inbox at once and someone who leaves loses
  it. A coach reads a thread only once brought in, by the topic
  «Προπόνηση» (the person's coaches, or the head coaches when they have
  none) or by «Φέρε τον coach». The rules themselves are
  `Messaging.Domain.BoxInboxPolicy`; this module gathers the facts they
  need from the other contexts.
  """

  alias Palee.Application.DispatchMessageDelivery
  alias Palee.{Coaching, Identity, Messaging, Organizations}
  alias Palee.Messaging.Domain.BoxInboxPolicy
  alias Palee.Organizations.TenantContext

  @no_access %{inbox?: false, coach?: false}

  @doc "What the acting member of `context` is at its box (inbox, coach)."
  def lens(%TenantContext{} = context) do
    %{
      inbox?: Organizations.can?(context, :message_from_box),
      coach?: Organizations.acting_user_coaches?(context)
    }
  end

  def lens(_context), do: @no_access

  @doc "The same for any account at a box, resolving its roles there."
  def lens(account, organization_id) when is_binary(organization_id) do
    case Organizations.resolve_tenant_context_by_id(account, organization_id) do
      {:ok, context} -> lens(context)
      _not_there -> @no_access
    end
  end

  def lens(_account, _organization_id), do: @no_access

  @doc """
  Before someone in the inbox lists their threads: a row (read marker) in
  every box thread of the gym, so threads opened before they joined show.
  Runs inside the gym's tenant scope.
  """
  def join_inbox(lens, user_id)

  def join_inbox(%{inbox?: true}, user_id), do: Messaging.join_box_threads(user_id)
  def join_inbox(_lens, _user_id), do: 0

  @doc "Whether the reader sees `thread` (a box thread by the rules above; others as before)."
  def visible?(thread, user_id, lens), do: BoxInboxPolicy.may_access?(thread, user_id, lens)

  @doc """
  Checks a box-side reader's access to a thread before the usual
  participant rules run, giving someone in the inbox their row on first
  open. Not a box thread, or the person's own: nothing to add.
  """
  def authorize(context, user_id, thread_id) do
    case Messaging.peek_thread(thread_id) do
      %{context_type: :box, context_id: ^user_id} ->
        :ok

      %{context_type: :box} = thread ->
        lens = lens(context)

        cond do
          not BoxInboxPolicy.may_access?(thread, user_id, lens) -> {:error, :forbidden}
          participant?(thread, user_id) -> :ok
          true -> joined(Messaging.add_participant(thread.id, user_id, :staff))
        end

      _other ->
        :ok
    end
  end

  @doc """
  Who in the box hears about the person's messages: the inbox, and the
  coaches brought in who still coach there. Runs inside the gym's scope.
  """
  def audience(%{organization_id: organization_id} = thread) do
    inbox = Organizations.list_user_ids_with_capability(organization_id, :message_from_box)
    coaches = MapSet.new(coach_user_ids(organization_id))

    brought_in = thread |> BoxInboxPolicy.coach_ids() |> Enum.filter(&MapSet.member?(coaches, &1))

    Enum.uniq(inbox ++ brought_in) -- [thread.context_id]
  end

  @doc "Whether the person is a client of the box (now or before) or a newcomer («Νέος»)."
  def standing(organization_id, person_id) do
    case Organizations.membership_standing(organization_id, person_id) do
      :none -> :newcomer
      _member_or_former -> :client
    end
  end

  @doc "Newcomers among `person_ids` and who of them the box blocked, for the inbox rows."
  def flags(organization_id, person_ids) do
    person_ids = Enum.uniq(person_ids)
    blocked = MapSet.new(Messaging.list_box_blocked_user_ids(person_ids))
    newcomers = Enum.filter(person_ids, &(standing(organization_id, &1) == :newcomer))

    Map.new(person_ids, fn id ->
      {id, %{newcomer: id in newcomers, blocked: MapSet.member?(blocked, id)}}
    end)
  end

  @doc """
  The person wrote about `topic`: «Προπόνηση» brings in their coaches, or
  the head coaches when they have none. Runs inside the gym's scope.
  """
  def route_topic(thread, "training") do
    thread.organization_id
    |> training_coaches(thread.context_id)
    |> Enum.reject(&(&1 == thread.context_id))
    |> Enum.each(&Messaging.add_participant(thread.id, &1, :coach))

    :ok
  end

  def route_topic(_thread, _topic), do: :ok

  @doc "The coaches the inbox may bring into a thread, the person's own first."
  def coach_candidates(context, user_id, thread_id) do
    with {:ok, thread} <- inbox_thread(context, user_id, thread_id) do
      own = MapSet.new(own_coach_ids(thread.organization_id, thread.context_id))
      in_thread = MapSet.new(BoxInboxPolicy.coach_ids(thread))
      ids = coach_user_ids(thread.organization_id) -- [thread.context_id]
      people = ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1})

      {:ok,
       ids
       |> Enum.filter(&Map.has_key?(people, &1))
       |> Enum.map(fn id ->
         %{
           id: id,
           nickname: people[id].nickname,
           avatar_url: Map.get(people[id], :avatar_url),
           coaches_person: MapSet.member?(own, id),
           in_thread: MapSet.member?(in_thread, id)
         }
       end)
       |> Enum.sort_by(&{not &1.coaches_person, String.downcase(&1.nickname || "")})}
    end
  end

  @doc "«Φέρε τον coach»: someone in the inbox brings a coach of the box into the thread."
  def bring_coach(context, user_id, thread_id, coach_id) do
    with {:ok, thread} <- inbox_thread(context, user_id, thread_id),
         true <- (coach_id in coach_user_ids(thread.organization_id)) || {:error, :not_a_coach},
         true <- coach_id != thread.context_id || {:error, :not_a_coach},
         {:ok, _participant} <- Messaging.add_participant(thread.id, coach_id, :coach),
         {:ok, thread} <- Messaging.get_thread(thread.id, user_id) do
      DispatchMessageDelivery.notify_coach_brought_in(thread, coach_id, user_id)
      {:ok, thread}
    end
  end

  @doc "The box stops hearing from a newcomer; a client is the box's to manage elsewhere."
  def block(context, user_id, thread_id) do
    with {:ok, thread} <- inbox_thread(context, user_id, thread_id),
         :newcomer <- standing(thread.organization_id, thread.context_id),
         {:ok, _block} <- Messaging.block_box_sender(thread.context_id, user_id) do
      {:ok, thread}
    else
      :client -> {:error, :client_not_blockable}
      error -> error
    end
  end

  def unblock(context, user_id, thread_id) do
    with {:ok, thread} <- inbox_thread(context, user_id, thread_id),
         :ok <- Messaging.unblock_box_sender(thread.context_id) do
      {:ok, thread}
    end
  end

  # -- internals

  defp inbox_thread(context, user_id, thread_id) do
    with :ok <- Organizations.authorize_capability(context, :message_from_box),
         :ok <- authorize(context, user_id, thread_id),
         {:ok, %{context_type: :box} = thread} <- Messaging.get_thread(thread_id, user_id) do
      {:ok, thread}
    else
      {:ok, _not_a_box_thread} -> {:error, :not_found}
      error -> error
    end
  end

  defp participant?(%{participants: participants}, user_id),
    do: Enum.any?(participants, &(&1.user_id == user_id))

  defp joined({:ok, _participant}), do: :ok
  defp joined(error), do: error

  defp training_coaches(organization_id, person_id) do
    case own_coach_ids(organization_id, person_id) do
      [] -> head_coach_ids(organization_id)
      coaches -> coaches
    end
  end

  defp own_coach_ids(organization_id, person_id) do
    %{organization_id: organization_id}
    |> Coaching.list_relationships(%{client_user_id: person_id})
    |> Enum.map(& &1.coach_user_id)
    |> Enum.uniq()
  end

  # Head coach = a coach whose scope is the whole box (ADR-217).
  defp head_coach_ids(organization_id) do
    for {id, %{roles: roles, coach_scope: :all}} <- Organizations.member_roles_by_user(organization_id),
        :coach in roles,
        do: id
  end

  defp coach_user_ids(organization_id) do
    for {id, %{roles: roles}} <- Organizations.member_roles_by_user(organization_id),
        :coach in roles,
        do: id
  end
end
