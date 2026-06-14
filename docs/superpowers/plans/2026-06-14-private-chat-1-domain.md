# Private Chat — Plan 1: Domain, DB Migrations & Ports

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the `Messaging` bounded context foundation — three DB tables, three Ecto schemas, ThreadPolicy domain module, and two port behaviours.

**Architecture:** New `Messaging` context under `lib/milos_training/messaging/`. Hexagonal: domain schemas have no external deps; ports are behaviours only. Infrastructure adapters come in Plan 2.

**Tech Stack:** Elixir/Phoenix 1.7, Ecto, PostgreSQL 16, ExUnit + DataCase

**Depends on:** nothing — this is the foundation layer.
**Enables:** Plans 2, 3, 4.

---

## File Map

### New files
- `apps/api/priv/repo/migrations/20260614000001_create_messaging_threads.exs`
- `apps/api/priv/repo/migrations/20260614000002_create_messaging_participants.exs`
- `apps/api/priv/repo/migrations/20260614000003_create_messaging_messages.exs`
- `apps/api/lib/milos_training/messaging/thread.ex`
- `apps/api/lib/milos_training/messaging/message.ex`
- `apps/api/lib/milos_training/messaging/participant.ex`
- `apps/api/lib/milos_training/messaging/domain/thread_policy.ex`
- `apps/api/lib/milos_training/messaging/ports/thread_store.ex`
- `apps/api/lib/milos_training/messaging/ports/message_store.ex`
- `apps/api/lib/milos_training/messaging.ex`
- `apps/api/test/milos_training/messaging/thread_test.exs`
- `apps/api/test/milos_training/messaging/message_test.exs`
- `apps/api/test/milos_training/messaging/participant_test.exs`
- `apps/api/test/milos_training/messaging/domain/thread_policy_test.exs`

---

## Task 1: Create `messaging_threads` migration

**Files:**
- Create: `apps/api/priv/repo/migrations/20260614000001_create_messaging_threads.exs`

- [ ] **Step 1: Write migration**

```elixir
# apps/api/priv/repo/migrations/20260614000001_create_messaging_threads.exs
defmodule MilosTraining.Repo.Migrations.CreateMessagingThreads do
  use Ecto.Migration

  def change do
    create table(:messaging_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :context_type, :string, null: false
      add :context_id, :binary_id, null: true
      add :created_by_id, :binary_id, null: false

      timestamps(updated_at: false)
    end

    create index(:messaging_threads, [:context_type, :context_id],
      unique: true,
      where: "context_type != 'direct'",
      name: :messaging_threads_context_unique
    )

    create index(:messaging_threads, [:created_by_id])
  end
end
```

- [ ] **Step 2: Run migration**

```bash
cd apps/api && mix ecto.migrate
```

Expected: `== Running 20260614000001 CreateMessagingThreads.change/0 forward`

---

## Task 2: Create `messaging_participants` migration

**Files:**
- Create: `apps/api/priv/repo/migrations/20260614000002_create_messaging_participants.exs`

- [ ] **Step 1: Write migration**

```elixir
# apps/api/priv/repo/migrations/20260614000002_create_messaging_participants.exs
defmodule MilosTraining.Repo.Migrations.CreateMessagingParticipants do
  use Ecto.Migration

  def change do
    create table(:messaging_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:messaging_threads, type: :binary_id, on_delete: :delete_all),
          null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      # plain field, no FK — avoids circular constraint with messaging_messages
      add :last_read_message_id, :binary_id, null: true
      add :joined_at, :utc_datetime_usec, null: false
    end

    create unique_index(:messaging_participants, [:thread_id, :user_id],
      name: :messaging_participants_thread_user_unique
    )

    create index(:messaging_participants, [:user_id])
  end
end
```

- [ ] **Step 2: Run migration**

```bash
cd apps/api && mix ecto.migrate
```

Expected: `== Running 20260614000002 CreateMessagingParticipants.change/0 forward`

---

## Task 3: Create `messaging_messages` migration

**Files:**
- Create: `apps/api/priv/repo/migrations/20260614000003_create_messaging_messages.exs`

- [ ] **Step 1: Write migration**

```elixir
# apps/api/priv/repo/migrations/20260614000003_create_messaging_messages.exs
defmodule MilosTraining.Repo.Migrations.CreateMessagingMessages do
  use Ecto.Migration

  def change do
    create table(:messaging_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_id, references(:messaging_threads, type: :binary_id, on_delete: :delete_all),
          null: false
      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :body, :text, null: false
      add :message_type, :string, null: false, default: "text"

      timestamps(updated_at: false)
    end

    create index(:messaging_messages, [:thread_id, :inserted_at])
    create index(:messaging_messages, [:sender_id])
  end
end
```

- [ ] **Step 2: Run migration**

```bash
cd apps/api && mix ecto.migrate
```

Expected: `== Running 20260614000003 CreateMessagingMessages.change/0 forward`

---

## Task 4: Thread schema with tests

**Files:**
- Create: `apps/api/lib/milos_training/messaging/thread.ex`
- Create: `apps/api/test/milos_training/messaging/thread_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# apps/api/test/milos_training/messaging/thread_test.exs
defmodule MilosTraining.Messaging.ThreadTest do
  use MilosTraining.DataCase, async: true

  alias MilosTraining.Messaging.Thread

  describe "changeset/2" do
    test "valid direct thread requires only context_type and created_by_id" do
      user_id = Ecto.UUID.generate()

      changeset =
        Thread.changeset(%Thread{}, %{
          context_type: :direct,
          created_by_id: user_id
        })

      assert changeset.valid?
    end

    test "assignment thread requires context_id" do
      user_id = Ecto.UUID.generate()

      changeset =
        Thread.changeset(%Thread{}, %{
          context_type: :assignment,
          created_by_id: user_id
        })

      refute changeset.valid?
      assert {:context_id, [{"can't be blank", _}]} =
               List.keyfind(changeset.errors, :context_id, 0)
    end

    test "assignment thread valid with context_id" do
      changeset =
        Thread.changeset(%Thread{}, %{
          context_type: :assignment,
          context_id: Ecto.UUID.generate(),
          created_by_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
    end

    test "invalid context_type rejected" do
      changeset =
        Thread.changeset(%Thread{}, %{
          context_type: :unknown,
          created_by_id: Ecto.UUID.generate()
        })

      refute changeset.valid?
    end

    test "missing created_by_id rejected" do
      changeset = Thread.changeset(%Thread{}, %{context_type: :direct})
      refute changeset.valid?
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/messaging/thread_test.exs 2>&1 | head -20
```

Expected: `** (CompileError)` — module does not exist yet.

- [ ] **Step 3: Implement Thread schema**

```elixir
# apps/api/lib/milos_training/messaging/thread.ex
defmodule MilosTraining.Messaging.Thread do
  use Ecto.Schema
  import Ecto.Changeset

  @context_types [:direct, :assignment, :class_slot]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_threads" do
    field :context_type, Ecto.Enum, values: @context_types
    field :context_id, :binary_id
    field :created_by_id, :binary_id

    has_many :participants, MilosTraining.Messaging.Participant, foreign_key: :thread_id
    has_many :messages, MilosTraining.Messaging.Message, foreign_key: :thread_id

    timestamps(updated_at: false)
  end

  def changeset(thread \\ %__MODULE__{}, params) do
    thread
    |> cast(params, [:context_type, :context_id, :created_by_id])
    |> validate_required([:context_type, :created_by_id])
    |> validate_context_id()
  end

  defp validate_context_id(changeset) do
    case get_field(changeset, :context_type) do
      :direct -> changeset
      nil -> changeset
      _ -> validate_required(changeset, [:context_id])
    end
  end
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/messaging/thread_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 5: Format and lint**

```bash
cd apps/api && mix format lib/milos_training/messaging/thread.ex && mix credo --strict lib/milos_training/messaging/thread.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/api/priv/repo/migrations/20260614000001_create_messaging_threads.exs \
        apps/api/priv/repo/migrations/20260614000002_create_messaging_participants.exs \
        apps/api/priv/repo/migrations/20260614000003_create_messaging_messages.exs \
        apps/api/lib/milos_training/messaging/thread.ex \
        apps/api/test/milos_training/messaging/thread_test.exs
git commit -m "feat(messaging): DB migrations + Thread schema"
```

---

## Task 5: Message schema with tests

**Files:**
- Create: `apps/api/lib/milos_training/messaging/message.ex`
- Create: `apps/api/test/milos_training/messaging/message_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# apps/api/test/milos_training/messaging/message_test.exs
defmodule MilosTraining.Messaging.MessageTest do
  use MilosTraining.DataCase, async: true

  alias MilosTraining.Messaging.Message

  describe "changeset/2" do
    test "valid text message" do
      changeset =
        Message.changeset(%Message{}, %{
          thread_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          body: "Hello!"
        })

      assert changeset.valid?
      assert get_field(changeset, :message_type) == :text
    end

    test "valid coaching_note message" do
      changeset =
        Message.changeset(%Message{}, %{
          thread_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          body: "Great squat depth today.",
          message_type: :coaching_note
        })

      assert changeset.valid?
    end

    test "body must not be blank" do
      changeset =
        Message.changeset(%Message{}, %{
          thread_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          body: ""
        })

      refute changeset.valid?
    end

    test "body max 4000 chars" do
      changeset =
        Message.changeset(%Message{}, %{
          thread_id: Ecto.UUID.generate(),
          sender_id: Ecto.UUID.generate(),
          body: String.duplicate("x", 4001)
        })

      refute changeset.valid?
    end

    test "thread_id required" do
      changeset =
        Message.changeset(%Message{}, %{sender_id: Ecto.UUID.generate(), body: "hi"})

      refute changeset.valid?
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/messaging/message_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement Message schema**

```elixir
# apps/api/lib/milos_training/messaging/message.ex
defmodule MilosTraining.Messaging.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @message_types [:text, :coaching_note]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_messages" do
    field :thread_id, :binary_id
    field :sender_id, :binary_id
    field :body, :string
    field :message_type, Ecto.Enum, values: @message_types, default: :text

    timestamps(updated_at: false)
  end

  def changeset(message \\ %__MODULE__{}, params) do
    message
    |> cast(params, [:thread_id, :sender_id, :body, :message_type])
    |> validate_required([:thread_id, :sender_id, :body])
    |> validate_length(:body, min: 1, max: 4000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
  end
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/messaging/message_test.exs
```

Expected: `5 tests, 0 failures`

---

## Task 6: Participant schema with tests

**Files:**
- Create: `apps/api/lib/milos_training/messaging/participant.ex`
- Create: `apps/api/test/milos_training/messaging/participant_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# apps/api/test/milos_training/messaging/participant_test.exs
defmodule MilosTraining.Messaging.ParticipantTest do
  use MilosTraining.DataCase, async: true

  alias MilosTraining.Messaging.Participant

  describe "changeset/2" do
    test "valid participant" do
      changeset =
        Participant.changeset(%Participant{}, %{
          thread_id: Ecto.UUID.generate(),
          user_id: Ecto.UUID.generate()
        })

      assert changeset.valid?
      assert get_field(changeset, :joined_at) != nil
    end

    test "thread_id required" do
      changeset = Participant.changeset(%Participant{}, %{user_id: Ecto.UUID.generate()})
      refute changeset.valid?
    end

    test "user_id required" do
      changeset = Participant.changeset(%Participant{}, %{thread_id: Ecto.UUID.generate()})
      refute changeset.valid?
    end

    test "explicit joined_at preserved" do
      dt = ~U[2026-01-01 10:00:00.000000Z]

      changeset =
        Participant.changeset(%Participant{}, %{
          thread_id: Ecto.UUID.generate(),
          user_id: Ecto.UUID.generate(),
          joined_at: dt
        })

      assert get_field(changeset, :joined_at) == dt
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/messaging/participant_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement Participant schema**

```elixir
# apps/api/lib/milos_training/messaging/participant.ex
defmodule MilosTraining.Messaging.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messaging_participants" do
    field :thread_id, :binary_id
    field :user_id, :binary_id
    field :last_read_message_id, :binary_id
    field :joined_at, :utc_datetime_usec
  end

  def changeset(participant \\ %__MODULE__{}, params) do
    participant
    |> cast(params, [:thread_id, :user_id, :last_read_message_id, :joined_at])
    |> validate_required([:thread_id, :user_id])
    |> put_joined_at()
    |> unique_constraint([:thread_id, :user_id],
      name: :messaging_participants_thread_user_unique
    )
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:user_id)
  end

  defp put_joined_at(changeset) do
    if get_field(changeset, :joined_at) do
      changeset
    else
      put_change(changeset, :joined_at, DateTime.utc_now())
    end
  end
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/messaging/participant_test.exs
```

Expected: `4 tests, 0 failures`

- [ ] **Step 5: Commit schemas**

```bash
git add apps/api/lib/milos_training/messaging/message.ex \
        apps/api/lib/milos_training/messaging/participant.ex \
        apps/api/test/milos_training/messaging/message_test.exs \
        apps/api/test/milos_training/messaging/participant_test.exs
git commit -m "feat(messaging): Message and Participant schemas"
```

---

## Task 7: ThreadPolicy domain module

**Files:**
- Create: `apps/api/lib/milos_training/messaging/domain/thread_policy.ex`
- Create: `apps/api/test/milos_training/messaging/domain/thread_policy_test.exs`

- [ ] **Step 1: Write failing test**

```elixir
# apps/api/test/milos_training/messaging/domain/thread_policy_test.exs
defmodule MilosTraining.Messaging.Domain.ThreadPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Messaging.Domain.ThreadPolicy

  describe "canonical_pair/2" do
    test "always returns sorted pair" do
      a = "aaaaaaaa-0000-0000-0000-000000000000"
      b = "bbbbbbbb-0000-0000-0000-000000000000"

      assert ThreadPolicy.canonical_pair(a, b) == [a, b]
      assert ThreadPolicy.canonical_pair(b, a) == [a, b]
    end
  end

  describe "participant?/2" do
    test "returns true when user_id is in participants list" do
      user_id = Ecto.UUID.generate()
      participants = [%{user_id: user_id}, %{user_id: Ecto.UUID.generate()}]

      assert ThreadPolicy.participant?(user_id, participants)
    end

    test "returns false when user_id not in participants" do
      participants = [%{user_id: Ecto.UUID.generate()}]

      refute ThreadPolicy.participant?(Ecto.UUID.generate(), participants)
    end

    test "returns false for empty participants" do
      refute ThreadPolicy.participant?(Ecto.UUID.generate(), [])
    end
  end
end
```

- [ ] **Step 2: Run test — expect compile error**

```bash
cd apps/api && mix test test/milos_training/messaging/domain/thread_policy_test.exs 2>&1 | head -10
```

- [ ] **Step 3: Implement ThreadPolicy**

```elixir
# apps/api/lib/milos_training/messaging/domain/thread_policy.ex
defmodule MilosTraining.Messaging.Domain.ThreadPolicy do
  @doc "Sort two user IDs for canonical direct-thread deduplication."
  def canonical_pair(user_a_id, user_b_id), do: Enum.sort([user_a_id, user_b_id])

  @doc "Is user_id a participant in the given participants list?"
  def participant?(user_id, participants) do
    Enum.any?(participants, &(&1.user_id == user_id))
  end
end
```

- [ ] **Step 4: Run test — expect pass**

```bash
cd apps/api && mix test test/milos_training/messaging/domain/thread_policy_test.exs
```

Expected: `3 tests, 0 failures`

---

## Task 8: Port behaviours + Messaging facade

**Files:**
- Create: `apps/api/lib/milos_training/messaging/ports/thread_store.ex`
- Create: `apps/api/lib/milos_training/messaging/ports/message_store.ex`
- Create: `apps/api/lib/milos_training/messaging.ex`

- [ ] **Step 1: Write ThreadStore port**

```elixir
# apps/api/lib/milos_training/messaging/ports/thread_store.ex
defmodule MilosTraining.Messaging.Ports.ThreadStore do
  @callback get_or_create_direct(String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback get_or_create_context(atom(), String.t(), String.t()) ::
              {:ok, map()} | {:error, term()}

  @callback list_for_user(String.t(), atom() | nil) :: [map()]

  @callback get_with_participants(String.t()) :: map() | nil

  @callback add_participant(String.t(), String.t()) ::
              {:ok, map()} | {:error, :already_participant} | {:error, term()}
end
```

- [ ] **Step 2: Write MessageStore port**

```elixir
# apps/api/lib/milos_training/messaging/ports/message_store.ex
defmodule MilosTraining.Messaging.Ports.MessageStore do
  @callback persist(map()) :: {:ok, map()} | {:error, term()}

  @callback list_page(String.t(), map()) :: [map()]

  @callback get(String.t()) :: map() | nil

  @callback unread_count(String.t(), String.t() | nil) :: non_neg_integer()
end
```

- [ ] **Step 3: Write Messaging facade**

```elixir
# apps/api/lib/milos_training/messaging.ex
defmodule MilosTraining.Messaging do
  alias MilosTraining.Messaging.Ports.{ThreadStore, MessageStore}

  defp thread_store do
    Application.get_env(
      :milos_training,
      :messaging_thread_store,
      MilosTraining.Infrastructure.Messaging.EctoThreadStore
    )
  end

  defp message_store do
    Application.get_env(
      :milos_training,
      :messaging_message_store,
      MilosTraining.Infrastructure.Messaging.EctoMessageStore
    )
  end

  def get_or_create_direct(user_a_id, user_b_id),
    do: thread_store().get_or_create_direct(user_a_id, user_b_id)

  def get_or_create_context(context_type, context_id, created_by_id),
    do: thread_store().get_or_create_context(context_type, context_id, created_by_id)

  def list_threads_for_user(user_id, context_type \\ nil),
    do: thread_store().list_for_user(user_id, context_type)

  def get_thread_with_participants(thread_id),
    do: thread_store().get_with_participants(thread_id)

  def add_participant(thread_id, user_id),
    do: thread_store().add_participant(thread_id, user_id)

  def persist_message(params), do: message_store().persist(params)

  def list_messages(thread_id, cursor_params \\ %{}),
    do: message_store().list_page(thread_id, cursor_params)

  def get_message(message_id), do: message_store().get(message_id)

  def unread_count(thread_id, last_read_message_id),
    do: message_store().unread_count(thread_id, last_read_message_id)
end
```

- [ ] **Step 4: Verify compilation**

```bash
cd apps/api && mix compile 2>&1 | grep -E "error|warning" | head -20
```

Expected: no errors on new files.

- [ ] **Step 5: Run all new tests**

```bash
cd apps/api && mix test test/milos_training/messaging/
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add apps/api/lib/milos_training/messaging/ \
        apps/api/test/milos_training/messaging/
git commit -m "feat(messaging): ports, ThreadPolicy, Messaging facade"
```

---

## Completion check

```bash
cd apps/api && mix test test/milos_training/messaging/ && mix compile --warnings-as-errors 2>&1 | tail -5
```

Expected: all tests pass, no compile warnings.
