# Private Chat — Plan 2: Infrastructure, Application Use Cases & Channel

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Ecto adapters, all application use cases, the OfflineNotifier, the ChatChannel, and the MessagingController (HTTP interface + OpenAPI specs).

**Architecture:** Infrastructure adapters implement the ports from Plan 1. Application use cases orchestrate domain + infrastructure. ChatChannel is a Phoenix Channel on `"chat:thread:{id}"`. MessagingController exposes REST endpoints.

**Tech Stack:** Elixir/Phoenix 1.7, Ecto, Phoenix Channels, ExUnit (DataCase + ConnCase + ChannelCase)

**Depends on:** Plan 1 (Messaging context foundation must exist)

---

## File Map

### New files (infrastructure)
- `apps/api/lib/milos_training/infrastructure/messaging/ecto_thread_store.ex`
- `apps/api/lib/milos_training/infrastructure/messaging/ecto_message_store.ex`
- `apps/api/lib/milos_training/infrastructure/messaging/offline_notifier.ex`

### New files (application)
- `apps/api/lib/milos_training/application/get_or_create_thread.ex`
- `apps/api/lib/milos_training/application/send_message.ex`
- `apps/api/lib/milos_training/application/get_thread_messages.ex`
- `apps/api/lib/milos_training/application/list_threads_for_user.ex`
- `apps/api/lib/milos_training/application/mark_thread_read.ex`
- `apps/api/lib/milos_training/application/broadcast_typing.ex`
- `apps/api/lib/milos_training/application/add_participant.ex`

### New files (channel + interface)
- `apps/api/lib/milos_training_web/channels/chat_channel.ex`
- `apps/api/lib/milos_training_web/controllers/messaging_controller.ex`
- `apps/api/test/support/channel_case.ex`
- `apps/api/test/milos_training/application/get_or_create_thread_test.exs`
- `apps/api/test/milos_training/application/send_message_test.exs`
- `apps/api/test/milos_training/application/list_threads_for_user_test.exs`
- `apps/api/test/milos_training_web/channels/chat_channel_test.exs`
- `apps/api/test/milos_training_web/controllers/messaging_controller_test.exs`

### Modified files
- `apps/api/lib/milos_training_web/user_socket.ex` — add `channel "chat:*"`
- `apps/api/lib/milos_training_web/router.ex` — add `/api/threads` routes
- `apps/api/lib/milos_training/notifications/notification.ex` — add `:chat_message` type

---

## Task 1: EctoThreadStore

**Files:**
- Create: `apps/api/lib/milos_training/infrastructure/messaging/ecto_thread_store.ex`
- Create: `apps/api/test/milos_training/application/get_or_create_thread_test.exs` (covers store indirectly via use case)

- [ ] **Step 1: Implement EctoThreadStore**

```elixir
# apps/api/lib/milos_training/infrastructure/messaging/ecto_thread_store.ex
defmodule MilosTraining.Infrastructure.Messaging.EctoThreadStore do
  @behaviour MilosTraining.Messaging.Ports.ThreadStore

  import Ecto.Query

  alias MilosTraining.Messaging.{Thread, Participant}
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Repo

  @impl true
  def get_or_create_direct(user_a_id, user_b_id) do
    [id1, id2] = ThreadPolicy.canonical_pair(user_a_id, user_b_id)

    case find_direct_thread(id1, id2) do
      %Thread{} = thread ->
        {:ok, thread}

      nil ->
        Repo.transaction(fn ->
          case Repo.insert(Thread.changeset(%{context_type: :direct, created_by_id: id1})) do
            {:ok, thread} ->
              insert_participant!(thread.id, id1)
              insert_participant!(thread.id, id2)
              preload_participants(thread)

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)
    end
  end

  @impl true
  def get_or_create_context(context_type, context_id, created_by_id) do
    case Repo.get_by(Thread, context_type: context_type, context_id: context_id) do
      %Thread{} = thread ->
        ensure_participant(thread.id, created_by_id)
        {:ok, preload_participants(thread)}

      nil ->
        Repo.transaction(fn ->
          attrs = %{
            context_type: context_type,
            context_id: context_id,
            created_by_id: created_by_id
          }

          case Repo.insert(Thread.changeset(attrs)) do
            {:ok, thread} ->
              insert_participant!(thread.id, created_by_id)
              preload_participants(thread)

            {:error, _} ->
              # Race condition: another process created it
              thread = Repo.get_by!(Thread, context_type: context_type, context_id: context_id)
              ensure_participant(thread.id, created_by_id)
              preload_participants(thread)
          end
        end)
    end
  end

  @impl true
  def list_for_user(user_id, context_type) do
    base =
      from t in Thread,
        join: p in Participant,
        on: p.thread_id == t.id and p.user_id == ^user_id,
        order_by: [desc: t.inserted_at],
        preload: [participants: ^from(p in Participant, order_by: p.joined_at)]

    base
    |> maybe_filter_context(context_type)
    |> Repo.all()
  end

  @impl true
  def get_with_participants(thread_id) do
    Thread
    |> where([t], t.id == ^thread_id)
    |> preload(participants: ^from(p in Participant, order_by: p.joined_at))
    |> Repo.one()
  end

  @impl true
  def add_participant(thread_id, user_id) do
    case Repo.get_by(Participant, thread_id: thread_id, user_id: user_id) do
      %Participant{} -> {:error, :already_participant}
      nil -> do_insert_participant(thread_id, user_id)
    end
  end

  defp find_direct_thread(user_a_id, user_b_id) do
    from(t in Thread,
      join: p1 in Participant,
      on: p1.thread_id == t.id and p1.user_id == ^user_a_id,
      join: p2 in Participant,
      on: p2.thread_id == t.id and p2.user_id == ^user_b_id,
      where: t.context_type == :direct,
      preload: [participants: ^from(p in Participant, order_by: p.joined_at)],
      limit: 1
    )
    |> Repo.one()
  end

  defp insert_participant!(thread_id, user_id) do
    %Participant{}
    |> Participant.changeset(%{thread_id: thread_id, user_id: user_id})
    |> Repo.insert!()
  end

  defp do_insert_participant(thread_id, user_id) do
    %Participant{}
    |> Participant.changeset(%{thread_id: thread_id, user_id: user_id})
    |> Repo.insert()
    |> case do
      {:ok, p} -> {:ok, p}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp ensure_participant(thread_id, user_id) do
    unless Repo.get_by(Participant, thread_id: thread_id, user_id: user_id) do
      insert_participant!(thread_id, user_id)
    end
  end

  defp preload_participants(thread) do
    Repo.preload(thread, participants: from(p in Participant, order_by: p.joined_at))
  end

  defp maybe_filter_context(query, nil), do: query

  defp maybe_filter_context(query, context_type),
    do: where(query, [t], t.context_type == ^context_type)
end
```

- [ ] **Step 2: Verify compilation**

```bash
cd apps/api && mix compile 2>&1 | grep "error" | head -10
```

Expected: no errors.

---

## Task 2: EctoMessageStore

**Files:**
- Create: `apps/api/lib/milos_training/infrastructure/messaging/ecto_message_store.ex`

- [ ] **Step 1: Implement EctoMessageStore**

```elixir
# apps/api/lib/milos_training/infrastructure/messaging/ecto_message_store.ex
defmodule MilosTraining.Infrastructure.Messaging.EctoMessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  import Ecto.Query

  alias MilosTraining.Messaging.Message
  alias MilosTraining.Repo

  @default_page_size 50

  @impl true
  def persist(params) do
    %Message{}
    |> Message.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, msg} -> {:ok, normalize(msg)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl true
  def list_page(thread_id, params) do
    limit = Map.get(params, :limit, @default_page_size) |> min(@default_page_size)
    cursor_inserted_at = Map.get(params, :cursor_inserted_at)

    base =
      from m in Message,
        where: m.thread_id == ^thread_id,
        order_by: [asc: m.inserted_at],
        limit: ^limit,
        select: m

    base
    |> maybe_apply_cursor(cursor_inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize/1)
  end

  @impl true
  def get(message_id) do
    case Repo.get(Message, message_id) do
      nil -> nil
      msg -> normalize(msg)
    end
  end

  @impl true
  def unread_count(thread_id, nil) do
    Repo.aggregate(from(m in Message, where: m.thread_id == ^thread_id), :count)
  end

  def unread_count(thread_id, last_read_message_id) do
    case Repo.get(Message, last_read_message_id) do
      nil ->
        0

      %Message{inserted_at: read_at} ->
        Repo.aggregate(
          from(m in Message,
            where: m.thread_id == ^thread_id and m.inserted_at > ^read_at
          ),
          :count
        )
    end
  end

  defp maybe_apply_cursor(query, nil), do: query

  defp maybe_apply_cursor(query, cursor_inserted_at) do
    where(query, [m], m.inserted_at > ^cursor_inserted_at)
  end

  defp normalize(%Message{} = msg) do
    %{
      id: msg.id,
      thread_id: msg.thread_id,
      sender_id: msg.sender_id,
      body: msg.body,
      message_type: to_string(msg.message_type),
      inserted_at: msg.inserted_at
    }
  end
end
```

- [ ] **Step 2: Verify compilation**

```bash
cd apps/api && mix compile 2>&1 | grep "error" | head -10
```

---

## Task 3: Application — GetOrCreateThread

**Files:**
- Create: `apps/api/lib/milos_training/application/get_or_create_thread.ex`
- Create: `apps/api/test/milos_training/application/get_or_create_thread_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# apps/api/test/milos_training/application/get_or_create_thread_test.exs
defmodule MilosTraining.Application.GetOrCreateThreadTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.GetOrCreateThread
  alias MilosTraining.Messaging

  describe "call/2 — direct" do
    test "creates a new direct thread between two users" do
      user_a = user_fixture()
      user_b = user_fixture()

      assert {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)
      assert thread.context_type == :direct
      assert length(thread.participants) == 2
      participant_ids = Enum.map(thread.participants, & &1.user_id)
      assert user_a.id in participant_ids
      assert user_b.id in participant_ids
    end

    test "returns existing thread when called twice with same users" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, thread1} = GetOrCreateThread.direct(user_a.id, user_b.id)
      {:ok, thread2} = GetOrCreateThread.direct(user_a.id, user_b.id)

      assert thread1.id == thread2.id
    end

    test "same thread regardless of argument order" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, thread1} = GetOrCreateThread.direct(user_a.id, user_b.id)
      {:ok, thread2} = GetOrCreateThread.direct(user_b.id, user_a.id)

      assert thread1.id == thread2.id
    end
  end

  describe "call/3 — context" do
    test "creates a new assignment thread" do
      user = user_fixture()
      context_id = Ecto.UUID.generate()

      assert {:ok, thread} = GetOrCreateThread.context(:assignment, context_id, user.id)
      assert thread.context_type == :assignment
      assert thread.context_id == context_id
      assert Enum.any?(thread.participants, &(&1.user_id == user.id))
    end

    test "returns same thread on second call for same context" do
      user_a = user_fixture()
      user_b = user_fixture()
      context_id = Ecto.UUID.generate()

      {:ok, thread1} = GetOrCreateThread.context(:assignment, context_id, user_a.id)
      {:ok, thread2} = GetOrCreateThread.context(:assignment, context_id, user_b.id)

      assert thread1.id == thread2.id
      assert length(thread2.participants) == 2
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/application/get_or_create_thread_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement GetOrCreateThread**

```elixir
# apps/api/lib/milos_training/application/get_or_create_thread.ex
defmodule MilosTraining.Application.GetOrCreateThread do
  alias MilosTraining.Messaging

  def direct(user_a_id, user_b_id) do
    Messaging.get_or_create_direct(user_a_id, user_b_id)
  end

  def context(context_type, context_id, created_by_id) do
    Messaging.get_or_create_context(context_type, context_id, created_by_id)
  end
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/application/get_or_create_thread_test.exs
```

Expected: `6 tests, 0 failures`

- [ ] **Step 5: Commit**

```bash
git add apps/api/lib/milos_training/infrastructure/messaging/ \
        apps/api/lib/milos_training/application/get_or_create_thread.ex \
        apps/api/test/milos_training/application/get_or_create_thread_test.exs
git commit -m "feat(messaging): EctoThreadStore, EctoMessageStore, GetOrCreateThread"
```

---

## Task 4: Application — SendMessage

**Files:**
- Create: `apps/api/lib/milos_training/application/send_message.ex`
- Create: `apps/api/test/milos_training/application/send_message_test.exs`

- [ ] **Step 1: Add `:chat_message` to Notification types**

In `apps/api/lib/milos_training/notifications/notification.ex`, add `:chat_message` to the `@types` list:

```elixir
# Find the @types list and add :chat_message:
@types [
  :booking_approved,
  :booking_rejected,
  :booking_pending,
  :booking_timeout,
  :workout_note,
  :workout_changed,
  :workout_deleted,
  :workout_rejected,
  :workout_moved,
  :athlete_message,
  :workout_completed,
  :admin_note,
  :challenge_completed,
  :chat_message        # ← add this
]
```

- [ ] **Step 2: Write failing test**

```elixir
# apps/api/test/milos_training/application/send_message_test.exs
defmodule MilosTraining.Application.SendMessageTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{GetOrCreateThread, SendMessage}
  alias MilosTraining.Messaging

  describe "call/3" do
    test "sends a text message in a direct thread" do
      sender = user_fixture()
      receiver = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(sender.id, receiver.id)

      assert {:ok, message} =
               SendMessage.call(thread.id, sender.id, %{body: "Hello!", message_type: :text})

      assert message.body == "Hello!"
      assert message.sender_id == sender.id
      assert message.thread_id == thread.id
      assert message.message_type == "text"
    end

    test "sends a coaching_note message type" do
      admin = admin_fixture()
      athlete = user_fixture(%{role: :athlete})
      {:ok, thread} = GetOrCreateThread.direct(admin.id, athlete.id)

      assert {:ok, message} =
               SendMessage.call(thread.id, admin.id, %{
                 body: "Great form today.",
                 message_type: :coaching_note
               })

      assert message.message_type == "coaching_note"
    end

    test "returns error when sender is not a participant" do
      user_a = user_fixture()
      user_b = user_fixture()
      outsider = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      assert {:error, :forbidden} =
               SendMessage.call(thread.id, outsider.id, %{body: "Intruder!"})
    end

    test "returns error for blank body" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      assert {:error, _changeset} = SendMessage.call(thread.id, user_a.id, %{body: ""})
    end
  end
end
```

- [ ] **Step 3: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/application/send_message_test.exs 2>&1 | head -10
```

- [ ] **Step 4: Implement OfflineNotifier**

```elixir
# apps/api/lib/milos_training/infrastructure/messaging/offline_notifier.ex
defmodule MilosTraining.Infrastructure.Messaging.OfflineNotifier do
  alias MilosTraining.Notifications

  def notify_offline_participants(thread, message, sender_id) do
    topic = "chat:thread:#{thread.id}"
    subscribed = subscribed_user_ids(topic)

    thread.participants
    |> Enum.reject(&(&1.user_id == sender_id))
    |> Enum.reject(&(&1.user_id in subscribed))
    |> Enum.each(&dispatch_notification(&1.user_id, message, thread))
  end

  defp subscribed_user_ids(topic) do
    case Phoenix.PubSub.list_topics(MilosTraining.PubSub) do
      _ ->
        # Check subscribers to the channel topic via PubSub
        # Falls back to empty list if topic has no active subscriptions
        try do
          :pg.get_members(:phx, topic)
          |> Enum.map(fn pid ->
            case :erlang.process_info(pid, :dictionary) do
              {:dictionary, dict} -> dict[:user_id]
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)
        rescue
          _ -> []
        end
    end
  end

  defp dispatch_notification(user_id, message, thread) do
    preview = String.slice(message.body, 0, 80)

    Notifications.dispatch_event(:chat_message, %{
      user_id: user_id,
      thread_id: thread.id,
      sender_id: message.sender_id,
      preview: preview,
      context_type: to_string(thread.context_type),
      context_id: thread.context_id
    })
  rescue
    _ -> :ok
  end
end
```

- [ ] **Step 5: Implement SendMessage**

```elixir
# apps/api/lib/milos_training/application/send_message.ex
defmodule MilosTraining.Application.SendMessage do
  alias MilosTraining.Application.RecordCommunicationMessage
  alias MilosTraining.Identity
  alias MilosTraining.Infrastructure.Messaging.OfflineNotifier
  alias MilosTraining.Messaging
  alias MilosTraining.Messaging.Domain.ThreadPolicy

  def call(thread_id, sender_id, params) do
    with %{} = thread <- Messaging.get_thread_with_participants(thread_id) || :not_found,
         true <- ThreadPolicy.participant?(sender_id, thread.participants) || :forbidden,
         {:ok, message} <- Messaging.persist_message(Map.merge(params, %{thread_id: thread_id, sender_id: sender_id})) do
      broadcast(thread_id, message, sender_id)
      OfflineNotifier.notify_offline_participants(thread, message, sender_id)
      record_analytics(thread, message, sender_id)
      {:ok, message}
    else
      :not_found -> {:error, :not_found}
      :forbidden -> {:error, :forbidden}
      false -> {:error, :forbidden}
      {:error, _} = error -> error
    end
  end

  defp broadcast(thread_id, message, _sender_id) do
    MilosTrainingWeb.Endpoint.broadcast(
      "chat:thread:#{thread_id}",
      "new_message",
      message
    )
  end

  defp record_analytics(thread, message, sender_id) do
    sender = Identity.find_by_id(sender_id)
    sender_role = if sender, do: to_string(sender.role), else: "unknown"

    direction =
      case thread.context_type do
        :direct -> if sender_role == "admin", do: "admin_to_admin", else: "user_to_admin"
        _ -> if sender_role == "admin", do: "admin_to_user", else: "user_to_admin"
      end

    RecordCommunicationMessage.call_unsafe(%{
      thread_id: thread.id,
      context_type: to_string(thread.context_type),
      context_id: thread.context_id,
      sender_id: sender_id,
      sender_role_snapshot: sender_role,
      direction: direction,
      body: message.body,
      message_params: %{messaging_message_id: message.id}
    })
  rescue
    _ -> :ok
  end
end
```

- [ ] **Step 6: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/application/send_message_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training/notifications/notification.ex \
        apps/api/lib/milos_training/infrastructure/messaging/offline_notifier.ex \
        apps/api/lib/milos_training/application/send_message.ex \
        apps/api/test/milos_training/application/send_message_test.exs
git commit -m "feat(messaging): SendMessage, OfflineNotifier, :chat_message notification type"
```

---

## Task 5: Remaining Application Use Cases

**Files:**
- Create: `apps/api/lib/milos_training/application/get_thread_messages.ex`
- Create: `apps/api/lib/milos_training/application/list_threads_for_user.ex`
- Create: `apps/api/lib/milos_training/application/mark_thread_read.ex`
- Create: `apps/api/lib/milos_training/application/broadcast_typing.ex`
- Create: `apps/api/lib/milos_training/application/add_participant.ex`
- Create: `apps/api/test/milos_training/application/list_threads_for_user_test.exs`

- [ ] **Step 1: Write failing test for ListThreadsForUser**

```elixir
# apps/api/test/milos_training/application/list_threads_for_user_test.exs
defmodule MilosTraining.Application.ListThreadsForUserTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{GetOrCreateThread, ListThreadsForUser, SendMessage}

  describe "call/2" do
    test "returns all threads for user" do
      user_a = user_fixture()
      user_b = user_fixture()
      user_c = user_fixture()

      {:ok, _} = GetOrCreateThread.direct(user_a.id, user_b.id)
      {:ok, _} = GetOrCreateThread.direct(user_a.id, user_c.id)

      threads = ListThreadsForUser.call(user_a.id)
      assert length(threads) == 2
    end

    test "filters by context_type" do
      user_a = user_fixture()
      user_b = user_fixture()

      {:ok, _} = GetOrCreateThread.direct(user_a.id, user_b.id)
      {:ok, _} = GetOrCreateThread.context(:assignment, Ecto.UUID.generate(), user_a.id)

      direct_threads = ListThreadsForUser.call(user_a.id, :direct)
      assert length(direct_threads) == 1
      assert hd(direct_threads).context_type == :direct

      assignment_threads = ListThreadsForUser.call(user_a.id, :assignment)
      assert length(assignment_threads) == 1
    end

    test "does not return threads user is not part of" do
      user_a = user_fixture()
      user_b = user_fixture()
      user_c = user_fixture()

      {:ok, _} = GetOrCreateThread.direct(user_b.id, user_c.id)

      assert ListThreadsForUser.call(user_a.id) == []
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/application/list_threads_for_user_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement GetThreadMessages**

```elixir
# apps/api/lib/milos_training/application/get_thread_messages.ex
defmodule MilosTraining.Application.GetThreadMessages do
  alias MilosTraining.Messaging
  alias MilosTraining.Messaging.Domain.ThreadPolicy

  def call(thread_id, actor_id, params \\ %{}) do
    case Messaging.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        if ThreadPolicy.participant?(actor_id, thread.participants) do
          messages = Messaging.list_messages(thread_id, params)
          {:ok, messages}
        else
          {:error, :forbidden}
        end
    end
  end
end
```

- [ ] **Step 4: Implement ListThreadsForUser**

```elixir
# apps/api/lib/milos_training/application/list_threads_for_user.ex
defmodule MilosTraining.Application.ListThreadsForUser do
  alias MilosTraining.Messaging

  def call(user_id, context_type \\ nil) do
    Messaging.list_threads_for_user(user_id, context_type)
  end
end
```

- [ ] **Step 5: Implement MarkThreadRead**

```elixir
# apps/api/lib/milos_training/application/mark_thread_read.ex
defmodule MilosTraining.Application.MarkThreadRead do
  import Ecto.Query

  alias MilosTraining.Messaging
  alias MilosTraining.Messaging.{Participant}
  alias MilosTraining.Messaging.Domain.ThreadPolicy
  alias MilosTraining.Repo

  def call(thread_id, actor_id, last_message_id) do
    case Messaging.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        if ThreadPolicy.participant?(actor_id, thread.participants) do
          update_last_read(thread_id, actor_id, last_message_id)
          broadcast_receipt(thread_id, actor_id, last_message_id)
          :ok
        else
          {:error, :forbidden}
        end
    end
  end

  defp update_last_read(thread_id, user_id, last_message_id) do
    from(p in Participant,
      where: p.thread_id == ^thread_id and p.user_id == ^user_id
    )
    |> Repo.update_all(set: [last_read_message_id: last_message_id])
  end

  defp broadcast_receipt(thread_id, actor_id, last_message_id) do
    MilosTrainingWeb.Endpoint.broadcast(
      "chat:thread:#{thread_id}",
      "read_receipt",
      %{user_id: actor_id, last_read_message_id: last_message_id}
    )
  end
end
```

- [ ] **Step 6: Implement BroadcastTyping**

```elixir
# apps/api/lib/milos_training/application/broadcast_typing.ex
defmodule MilosTraining.Application.BroadcastTyping do
  alias MilosTraining.Messaging
  alias MilosTraining.Messaging.Domain.ThreadPolicy

  def call(thread_id, actor_id, nickname, typing) when is_boolean(typing) do
    case Messaging.get_thread_with_participants(thread_id) do
      nil ->
        {:error, :not_found}

      thread ->
        if ThreadPolicy.participant?(actor_id, thread.participants) do
          MilosTrainingWeb.Endpoint.broadcast(
            "chat:thread:#{thread_id}",
            "typing",
            %{user_id: actor_id, nickname: nickname, typing: typing}
          )

          :ok
        else
          {:error, :forbidden}
        end
    end
  end
end
```

- [ ] **Step 7: Implement AddParticipant**

```elixir
# apps/api/lib/milos_training/application/add_participant.ex
defmodule MilosTraining.Application.AddParticipant do
  alias MilosTraining.Messaging

  def call(thread_id, user_id) do
    case Messaging.get_thread_with_participants(thread_id) do
      nil -> {:error, :not_found}
      _thread -> Messaging.add_participant(thread_id, user_id)
    end
  end
end
```

- [ ] **Step 8: Run ListThreadsForUser test — expect pass**

```bash
cd apps/api && mix test test/milos_training/application/list_threads_for_user_test.exs
```

Expected: `3 tests, 0 failures`

- [ ] **Step 9: Commit**

```bash
git add apps/api/lib/milos_training/application/get_thread_messages.ex \
        apps/api/lib/milos_training/application/list_threads_for_user.ex \
        apps/api/lib/milos_training/application/mark_thread_read.ex \
        apps/api/lib/milos_training/application/broadcast_typing.ex \
        apps/api/lib/milos_training/application/add_participant.ex \
        apps/api/test/milos_training/application/list_threads_for_user_test.exs
git commit -m "feat(messaging): remaining application use cases"
```

---

## Task 6: ChatChannel

**Files:**
- Create: `apps/api/test/support/channel_case.ex`
- Create: `apps/api/lib/milos_training_web/channels/chat_channel.ex`
- Create: `apps/api/test/milos_training_web/channels/chat_channel_test.exs`
- Modify: `apps/api/lib/milos_training_web/user_socket.ex`

- [ ] **Step 1: Add ChannelCase test support**

```elixir
# apps/api/test/support/channel_case.ex
defmodule MilosTrainingWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import MilosTraining.TestFixtures

      @endpoint MilosTrainingWeb.Endpoint
    end
  end

  setup tags do
    MilosTraining.DataCase.setup_sandbox(tags)
    :ok
  end
end
```

- [ ] **Step 2: Write failing ChatChannel test**

```elixir
# apps/api/test/milos_training_web/channels/chat_channel_test.exs
defmodule MilosTrainingWeb.ChatChannelTest do
  use MilosTrainingWeb.ChannelCase, async: false

  alias MilosTraining.Application.GetOrCreateThread
  alias MilosTraining.Infrastructure.Auth.Guardian

  defp connect_user(user) do
    {:ok, token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")
    {:ok, socket} = connect(MilosTrainingWeb.UserSocket, %{"token" => token})
    socket
  end

  describe "join" do
    test "participant can join their thread" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      socket = connect_user(user_a)
      assert {:ok, _, _socket} = subscribe_and_join(socket, "chat:thread:#{thread.id}", %{})
    end

    test "non-participant is rejected" do
      user_a = user_fixture()
      user_b = user_fixture()
      outsider = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      socket = connect_user(outsider)
      assert {:error, %{reason: "forbidden"}} =
               subscribe_and_join(socket, "chat:thread:#{thread.id}", %{})
    end
  end

  describe "send_message event" do
    test "persists and broadcasts new_message to all subscribers" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      socket_a = connect_user(user_a)
      {:ok, _, socket_a} = subscribe_and_join(socket_a, "chat:thread:#{thread.id}", %{})

      push(socket_a, "send_message", %{"body" => "Hey there!"})

      assert_broadcast "new_message", %{body: "Hey there!", sender_id: sender_id}
      assert sender_id == user_a.id
    end
  end

  describe "typing event" do
    test "broadcasts typing indicator without DB write" do
      user_a = user_fixture()
      user_b = user_fixture()
      {:ok, thread} = GetOrCreateThread.direct(user_a.id, user_b.id)

      socket_a = connect_user(user_a)
      {:ok, _, socket_a} = subscribe_and_join(socket_a, "chat:thread:#{thread.id}", %{})

      push(socket_a, "typing_start", %{})
      assert_broadcast "typing", %{user_id: _, typing: true}
    end
  end
end
```

- [ ] **Step 3: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training_web/channels/chat_channel_test.exs 2>&1 | head -10
```

- [ ] **Step 4: Implement ChatChannel**

```elixir
# apps/api/lib/milos_training_web/channels/chat_channel.ex
defmodule MilosTrainingWeb.ChatChannel do
  use Phoenix.Channel

  alias MilosTraining.Application.{SendMessage, MarkThreadRead, BroadcastTyping}
  alias MilosTraining.Messaging
  alias MilosTraining.Messaging.Domain.ThreadPolicy

  @impl true
  def join("chat:thread:" <> thread_id, _payload, socket) do
    user_id = socket.assigns.current_user.id

    case Messaging.get_thread_with_participants(thread_id) do
      nil ->
        {:error, %{reason: "not_found"}}

      thread ->
        if ThreadPolicy.participant?(user_id, thread.participants) do
          {:ok, assign(socket, :thread_id, thread_id)}
        else
          {:error, %{reason: "forbidden"}}
        end
    end
  end

  @impl true
  def handle_in("send_message", %{"body" => body} = params, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.current_user.id
    message_type = Map.get(params, "message_type", "text") |> String.to_existing_atom()

    case SendMessage.call(thread_id, user_id, %{body: body, message_type: message_type}) do
      {:ok, _message} -> {:noreply, socket}
      {:error, reason} -> {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("typing_start", _params, socket) do
    user = socket.assigns.current_user

    BroadcastTyping.call(
      socket.assigns.thread_id,
      user.id,
      user.nickname,
      true
    )

    {:noreply, socket}
  end

  def handle_in("typing_stop", _params, socket) do
    user = socket.assigns.current_user

    BroadcastTyping.call(
      socket.assigns.thread_id,
      user.id,
      user.nickname,
      false
    )

    {:noreply, socket}
  end

  def handle_in("mark_read", %{"last_message_id" => last_message_id}, socket) do
    MarkThreadRead.call(
      socket.assigns.thread_id,
      socket.assigns.current_user.id,
      last_message_id
    )

    {:noreply, socket}
  end
end
```

- [ ] **Step 5: Register channel in UserSocket**

In `apps/api/lib/milos_training_web/user_socket.ex`, add the chat channel:

```elixir
# After the existing channel declarations, add:
channel "chat:*", MilosTrainingWeb.ChatChannel
```

Full updated file:
```elixir
defmodule MilosTrainingWeb.UserSocket do
  use Phoenix.Socket

  alias MilosTraining.Infrastructure.Auth.Guardian

  channel "schedule:lobby", MilosTrainingWeb.ScheduleChannel
  channel "notifications:*", MilosTrainingWeb.NotificationChannel
  channel "sync:*", MilosTrainingWeb.SyncChannel
  channel "execution:*", MilosTrainingWeb.ExecutionChannel
  channel "chat:*", MilosTrainingWeb.ChatChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    with {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      {:ok, assign(socket, :current_user, user)}
    else
      _error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
```

- [ ] **Step 6: Run channel tests**

```bash
cd apps/api && mix test test/milos_training_web/channels/chat_channel_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training_web/channels/chat_channel.ex \
        apps/api/lib/milos_training_web/user_socket.ex \
        apps/api/test/support/channel_case.ex \
        apps/api/test/milos_training_web/channels/chat_channel_test.exs
git commit -m "feat(messaging): ChatChannel with join auth, send_message, typing, mark_read"
```

---

## Task 7: MessagingController + Routes

**Files:**
- Create: `apps/api/lib/milos_training_web/controllers/messaging_controller.ex`
- Create: `apps/api/test/milos_training_web/controllers/messaging_controller_test.exs`
- Modify: `apps/api/lib/milos_training_web/router.ex`

- [ ] **Step 1: Write failing controller test**

```elixir
# apps/api/test/milos_training_web/controllers/messaging_controller_test.exs
defmodule MilosTrainingWeb.MessagingControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  describe "GET /api/threads" do
    test "returns threads for authenticated user", %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      conn
      |> put_bearer_token(user_a)
      |> post("/api/threads", %{participant_id: user_b.id})

      response =
        conn
        |> put_bearer_token(user_a)
        |> get("/api/threads")
        |> json_response(200)

      assert is_list(response["threads"])
      assert length(response["threads"]) == 1
    end

    test "requires authentication", %{conn: conn} do
      conn |> get("/api/threads") |> json_response(401)
    end
  end

  describe "POST /api/threads" do
    test "creates direct thread", %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      response =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads", %{participant_id: user_b.id})
        |> json_response(200)

      assert response["thread"]["context_type"] == "direct"
    end

    test "returns same thread on second call", %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      r1 =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads", %{participant_id: user_b.id})
        |> json_response(200)

      r2 =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads", %{participant_id: user_b.id})
        |> json_response(200)

      assert r1["thread"]["id"] == r2["thread"]["id"]
    end
  end

  describe "GET /api/threads/context/:type/:id" do
    test "creates thread for assignment context", %{conn: conn} do
      user = user_fixture()
      context_id = Ecto.UUID.generate()

      response =
        conn
        |> put_bearer_token(user)
        |> get("/api/threads/context/assignment/#{context_id}")
        |> json_response(200)

      assert response["thread"]["context_type"] == "assignment"
      assert response["thread"]["context_id"] == context_id
    end
  end

  describe "POST /api/threads/:id/messages" do
    test "sends a message in an existing thread", %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()

      %{"thread" => %{"id" => thread_id}} =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads", %{participant_id: user_b.id})
        |> json_response(200)

      response =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads/#{thread_id}/messages", %{body: "Hello!"})
        |> json_response(201)

      assert response["message"]["body"] == "Hello!"
    end

    test "outsider cannot send message", %{conn: conn} do
      user_a = user_fixture()
      user_b = user_fixture()
      outsider = user_fixture()

      %{"thread" => %{"id" => thread_id}} =
        conn
        |> put_bearer_token(user_a)
        |> post("/api/threads", %{participant_id: user_b.id})
        |> json_response(200)

      conn
      |> put_bearer_token(outsider)
      |> post("/api/threads/#{thread_id}/messages", %{body: "Hack!"})
      |> json_response(403)
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error (no controller or routes yet)**

```bash
cd apps/api && mix test test/milos_training_web/controllers/messaging_controller_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement MessagingController**

```elixir
# apps/api/lib/milos_training_web/controllers/messaging_controller.ex
defmodule MilosTrainingWeb.MessagingController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{
    GetOrCreateThread,
    GetThreadMessages,
    ListThreadsForUser,
    MarkThreadRead,
    SendMessage
  }
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Messaging"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "List threads for the current user",
    parameters: [
      %Parameter{name: :context_type, in: :query, required: false,
        schema: %Schema{type: :string, enum: ["direct", "assignment", "class_slot"]}},
      %Parameter{name: :limit, in: :query, required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100}},
      %Parameter{name: :cursor, in: :query, required: false,
        schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Threads", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  operation(:create,
    summary: "Get or create a direct thread with another user",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{
        schema: %Schema{type: :object, properties: %{participant_id: %Schema{type: :string, format: :uuid}}, required: [:participant_id]}
      }}
    },
    responses: [ok: {"Thread", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  operation(:context_thread,
    summary: "Get or create a thread for a specific context (assignment or class_slot)",
    parameters: [
      %Parameter{name: :context_type, in: :path, required: true, schema: %Schema{type: :string}},
      %Parameter{name: :context_id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}
    ],
    responses: [ok: {"Thread", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  operation(:messages,
    summary: "List messages in a thread",
    parameters: [
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}},
      %Parameter{name: :limit, in: :query, required: false, schema: %Schema{type: :integer}},
      %Parameter{name: :cursor_inserted_at, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [ok: {"Messages", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  operation(:send_message,
    summary: "Send a message in a thread",
    parameters: [
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{
        schema: %Schema{type: :object,
          properties: %{
            body: %Schema{type: :string, minLength: 1, maxLength: 4000},
            message_type: %Schema{type: :string, enum: ["text", "coaching_note"]}
          },
          required: [:body]}
      }}
    },
    responses: [created: {"Message", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  operation(:mark_read,
    summary: "Mark a thread as read up to a message",
    parameters: [
      %Parameter{name: :id, in: :path, required: true, schema: %Schema{type: :string, format: :uuid}}
    ],
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{
        schema: %Schema{type: :object,
          properties: %{last_message_id: %Schema{type: :string, format: :uuid}},
          required: [:last_message_id]}
      }}
    },
    responses: [ok: {"Result", "application/json", %Schema{type: :object, additionalProperties: true}}]
  )

  def index(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    context_type = parse_context_type(params["context_type"])
    threads = ListThreadsForUser.call(actor.id, context_type)
    json(conn, %{threads: serialize_threads(threads)})
  end

  def create(conn, params) do
    actor = GuardianPlug.current_resource(conn)
    participant_id = params["participant_id"] || get_in(params, ["body", "participant_id"])

    with {:ok, thread} <- GetOrCreateThread.direct(actor.id, participant_id) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def context_thread(conn, %{"context_type" => context_type, "context_id" => context_id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, thread} <- GetOrCreateThread.context(String.to_existing_atom(context_type), context_id, actor.id) do
      json(conn, %{thread: serialize_thread(thread)})
    end
  end

  def messages(conn, %{"id" => thread_id} = params) do
    actor = GuardianPlug.current_resource(conn)

    cursor_params = %{
      limit: parse_int(params["limit"], 50),
      cursor_inserted_at: params["cursor_inserted_at"]
    }

    with {:ok, messages} <- GetThreadMessages.call(thread_id, actor.id, cursor_params) do
      json(conn, %{messages: messages})
    end
  end

  def send_message(conn, %{"id" => thread_id} = params) do
    actor = GuardianPlug.current_resource(conn)
    body = get_body(conn, params)
    message_type = parse_message_type(body["message_type"])

    with {:ok, message} <- SendMessage.call(thread_id, actor.id, %{body: body["body"], message_type: message_type}) do
      conn |> put_status(:created) |> json(%{message: message})
    end
  end

  def mark_read(conn, %{"id" => thread_id} = params) do
    actor = GuardianPlug.current_resource(conn)
    body = get_body(conn, params)

    with :ok <- MarkThreadRead.call(thread_id, actor.id, body["last_message_id"]) do
      json(conn, %{read: true})
    end
  end

  defp serialize_threads(threads), do: Enum.map(threads, &serialize_thread/1)

  defp serialize_thread(thread) do
    %{
      id: thread.id,
      context_type: to_string(thread.context_type),
      context_id: thread.context_id,
      inserted_at: thread.inserted_at,
      participants: Enum.map(thread.participants || [], fn p ->
        %{user_id: p.user_id, last_read_message_id: p.last_read_message_id, joined_at: p.joined_at}
      end)
    }
  end

  defp parse_context_type(nil), do: nil
  defp parse_context_type(v) do
    try do
      String.to_existing_atom(v)
    rescue
      _ -> nil
    end
  end

  defp parse_message_type(nil), do: :text
  defp parse_message_type("coaching_note"), do: :coaching_note
  defp parse_message_type(_), do: :text

  defp parse_int(nil, default), do: default
  defp parse_int(v, _) when is_integer(v), do: min(v, 100)
  defp parse_int(v, default) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> min(n, 100)
      _ -> default
    end
  end

  defp get_body(conn, params) do
    case conn.body_params do
      %{} = body when map_size(body) > 0 -> body
      _ -> Map.get(params, "body") || params
    end
  end
end
```

- [ ] **Step 4: Add routes to router**

In `apps/api/lib/milos_training_web/router.ex`, inside the `scope "/api"` + authenticated + user_only block, add:

```elixir
# Messaging (private chat)
get "/threads", MessagingController, :index
post "/threads", MessagingController, :create
get "/threads/context/:context_type/:context_id", MessagingController, :context_thread
get "/threads/:id/messages", MessagingController, :messages
post "/threads/:id/messages", MessagingController, :send_message
post "/threads/:id/read", MessagingController, :mark_read
```

- [ ] **Step 5: Run controller tests**

```bash
cd apps/api && mix test test/milos_training_web/controllers/messaging_controller_test.exs
```

Expected: `6 tests, 0 failures`

- [ ] **Step 6: Run full test suite**

```bash
cd apps/api && mix test 2>&1 | tail -5
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/lib/milos_training_web/controllers/messaging_controller.ex \
        apps/api/lib/milos_training_web/router.ex \
        apps/api/test/milos_training_web/controllers/messaging_controller_test.exs
git commit -m "feat(messaging): MessagingController, OpenAPI specs, routes"
```

---

## Completion check

```bash
cd apps/api && mix test && mix format --check-formatted && mix credo --strict 2>&1 | tail -10
```

Expected: all tests pass, no format/credo issues.
