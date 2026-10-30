defmodule Palee.Infrastructure.Messaging.EctoThreadStore do
  @behaviour Palee.Messaging.Ports.ThreadStore

  import Ecto.Query

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Messaging.{BoxBlock, Message, Participant, Thread}
  alias Palee.Repo

  @impl true
  def get_thread(id) do
    Thread |> scoped_to_tenant() |> Repo.get(id)
  end

  @impl true
  def get_thread_with_participants(id) do
    Thread
    |> scoped_to_tenant()
    |> where([t], t.id == ^id)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def find_direct_thread(user_id_a, user_id_b) do
    participant_ids = [user_id_a, user_id_b]

    thread_ids_for_a =
      Participant
      |> scoped_to_tenant()
      |> where([p], p.user_id == ^user_id_a)
      |> select([p], p.thread_id)

    thread_ids_for_b =
      Participant
      |> scoped_to_tenant()
      |> where([p], p.user_id == ^user_id_b)
      |> select([p], p.thread_id)

    Thread
    |> scoped_to_tenant()
    |> where([t], t.context_type == :direct)
    |> where([t], t.id in subquery(thread_ids_for_a))
    |> where([t], t.id in subquery(thread_ids_for_b))
    |> join(:left, [t], p in assoc(t, :participants))
    |> group_by([t, _p], t.id)
    |> having([_t, p], count(p.id) == ^length(participant_ids))
    |> order_by([t, _p], asc: t.inserted_at, asc: t.id)
    |> limit(1)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def find_context_thread(context_type, context_id) do
    Thread
    |> scoped_to_tenant()
    |> where([t], t.context_type == ^context_type and t.context_id == ^context_id)
    |> preload(:participants)
    |> Repo.one()
  end

  @impl true
  def list_threads_for_user(user_id, context_type) do
    thread_ids =
      Participant
      |> scoped_to_tenant()
      |> where([p], p.user_id == ^user_id)
      |> select([p], p.thread_id)

    base =
      Thread
      |> scoped_to_tenant()
      |> where([t], t.id in subquery(thread_ids))

    base
    |> maybe_filter_context(context_type)
    |> order_by([t], desc: t.inserted_at)
    |> preload([:participants, messages: ^last_message_query()])
    |> Repo.all()
  end

  @impl true
  def create_thread(attrs) do
    %Thread{}
    |> Thread.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def get_or_create_thread(attrs, participant_ids) do
    Repo.transaction(fn ->
      thread = find_legacy_direct_thread(attrs, participant_ids) || insert_or_get_thread(attrs)

      participant_ids
      |> Enum.uniq()
      |> Enum.each(fn user_id ->
        %Participant{}
        |> Participant.changeset(%{
          organization_id: thread.organization_id,
          thread_id: thread.id,
          user_id: user_id
        })
        |> Repo.insert!(on_conflict: :nothing, conflict_target: [:thread_id, :user_id])
      end)

      thread
      |> Repo.preload(:participants, force: true)
    end)
    |> case do
      {:ok, thread} -> {:ok, thread}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def add_participant(thread_id, user_id), do: add_participant(thread_id, user_id, nil)

  @impl true
  def add_participant(thread_id, user_id, joined_as) do
    attrs =
      %{thread_id: thread_id, user_id: user_id, joined_as: joined_as}
      |> put_current_organization_id()

    # The latest reason wins (a coach brought into a thread they read as
    # staff); a call without a reason never overwrites one.
    conflict =
      if joined_as,
        do: [set: [joined_as: joined_as]],
        else: :nothing

    %Participant{}
    |> Participant.changeset(attrs)
    |> Repo.insert(on_conflict: conflict, conflict_target: [:thread_id, :user_id])
  end

  @impl true
  def join_box_threads(user_id) do
    case current_organization_id() do
      organization_id when is_binary(organization_id) ->
        %{num_rows: count} =
          Repo.query!(
            """
            INSERT INTO messaging_participants
              (id, organization_id, thread_id, user_id, joined_as, inserted_at)
            SELECT gen_random_uuid(), t.organization_id, t.id, $1, 'staff', now()
            FROM messaging_threads t
            WHERE t.organization_id = $2 AND t.context_type = 'box' AND t.context_id <> $1
            ON CONFLICT (thread_id, user_id) DO NOTHING
            """,
            [Ecto.UUID.dump!(user_id), Ecto.UUID.dump!(organization_id)]
          )

        count

      _missing_scope ->
        0
    end
  end

  @impl true
  def box_blocked?(user_id) do
    BoxBlock |> scoped_to_tenant() |> where([b], b.user_id == ^user_id) |> Repo.exists?()
  end

  @impl true
  def list_box_blocked_user_ids([]), do: []

  def list_box_blocked_user_ids(user_ids) do
    BoxBlock
    |> scoped_to_tenant()
    |> where([b], b.user_id in ^user_ids)
    |> select([b], b.user_id)
    |> Repo.all()
  end

  @impl true
  def block_box_sender(user_id, blocked_by_id) do
    %BoxBlock{}
    |> BoxBlock.changeset(
      put_current_organization_id(%{user_id: user_id, blocked_by_id: blocked_by_id})
    )
    |> Repo.insert(
      on_conflict: {:replace, [:blocked_by_id]},
      conflict_target: [:organization_id, :user_id],
      returning: true
    )
  end

  @impl true
  def unblock_box_sender(user_id) do
    BoxBlock |> scoped_to_tenant() |> where([b], b.user_id == ^user_id) |> Repo.delete_all()
    :ok
  end

  @impl true
  def mark_read(thread_id, user_id, message_id) do
    Repo.transaction(fn ->
      participant =
        Participant
        |> scoped_to_tenant()
        |> where([p], p.thread_id == ^thread_id and p.user_id == ^user_id)
        |> lock("FOR UPDATE")
        |> Repo.one()

      target =
        Message
        |> scoped_to_tenant()
        |> where([m], m.id == ^message_id and m.thread_id == ^thread_id)
        |> Repo.one()

      cond do
        is_nil(participant) ->
          Repo.rollback(:not_found)

        is_nil(target) ->
          Repo.rollback(:invalid_message)

        is_nil(participant.last_read_message_id) ->
          advance_read_pointer(participant, target)

        true ->
          current = Message |> scoped_to_tenant() |> Repo.get(participant.last_read_message_id)

          if later_message?(target, current) do
            advance_read_pointer(participant, target)
          else
            participant.last_read_message_id
          end
      end
    end)
    |> case do
      {:ok, effective_message_id} -> {:ok, effective_message_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def count_unread_threads(user_id) do
    Participant
    |> scoped_to_tenant()
    |> where([p], p.user_id == ^user_id)
    |> join(:left, [p], lr in Message, on: lr.id == p.last_read_message_id)
    |> join(:inner, [p, _lr], m in Message,
      on: m.thread_id == p.thread_id and m.sender_id != ^user_id
    )
    |> where([p, lr, m], is_nil(p.last_read_message_id) or m.sequence_number > lr.sequence_number)
    |> select([p], count(p.thread_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @impl true
  def list_box_conversation_organization_ids do
    %{rows: rows} =
      Repo.query!("SELECT id FROM palee_my_box_conversation_organization_ids() AS id")

    Enum.map(rows, fn [id] -> Ecto.UUID.load!(id) end)
  end

  defp maybe_filter_context(query, nil), do: query

  defp maybe_filter_context(query, context_type) do
    where(query, [t], t.context_type == ^context_type)
  end

  defp last_message_query do
    Message
    |> order_by([m], desc: m.sequence_number)
    |> limit(1)
  end

  defp insert_or_get_thread(%{context_type: :direct, direct_key: direct_key} = attrs) do
    insert_or_get_thread(
      attrs,
      {:unsafe_fragment, "(organization_id, direct_key) WHERE direct_key IS NOT NULL"},
      fn ->
        Thread
        |> scoped_to_tenant()
        |> Repo.get_by!(direct_key: direct_key)
      end
    )
  end

  defp insert_or_get_thread(%{context_type: context_type, context_id: context_id} = attrs) do
    conflict_target =
      {:unsafe_fragment,
       "(organization_id, context_type, context_id) WHERE context_type != 'direct'"}

    insert_or_get_thread(attrs, conflict_target, fn ->
      Thread
      |> scoped_to_tenant()
      |> Repo.get_by!(context_type: context_type, context_id: context_id)
    end)
  end

  defp insert_or_get_thread(attrs, conflict_target, fetch_existing) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    id = Ecto.UUID.generate()

    row =
      attrs
      |> put_current_organization_id()
      |> Map.put(:id, id)
      |> Map.put(:inserted_at, now)

    case Repo.insert_all(Thread, [row],
           on_conflict: :nothing,
           conflict_target: conflict_target,
           returning: [:id]
         ) do
      {1, _rows} -> Thread |> scoped_to_tenant() |> Repo.get!(id)
      {0, _rows} -> fetch_existing.()
    end
  end

  defp advance_read_pointer(participant, message) do
    participant
    |> Ecto.Changeset.change(last_read_message_id: message.id)
    |> Repo.update!()

    message.id
  end

  defp later_message?(_target, nil), do: true

  defp later_message?(target, %{thread_id: thread_id}) when target.thread_id != thread_id,
    do: true

  defp later_message?(target, current) do
    target.sequence_number > current.sequence_number
  end

  defp find_legacy_direct_thread(%{context_type: :direct, direct_key: direct_key}, [a, b]) do
    case find_direct_thread(a, b) do
      %{direct_key: nil} = thread ->
        thread
        |> Ecto.Changeset.change(direct_key: direct_key)
        |> Repo.update!()

      thread ->
        thread
    end
  end

  defp find_legacy_direct_thread(_attrs, _participant_ids), do: nil

  defp scoped_to_tenant(query) do
    case current_organization_id() do
      organization_id when is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      _missing_scope ->
        where(query, [row], false)
    end
  end

  defp current_organization_id, do: RepoContext.current_setting("app.organization_id")

  defp put_current_organization_id(attrs) do
    case current_organization_id() do
      organization_id when is_binary(organization_id) ->
        Map.put_new(attrs, :organization_id, organization_id)

      _missing_scope ->
        Map.put_new(attrs, :organization_id, nil)
    end
  end
end
