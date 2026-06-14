defmodule MilosTraining.Messaging.Domain.ThreadPolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Messaging.Domain.ThreadPolicy

  describe "canonical_pair/2" do
    test "returns a tuple of sorted ids" do
      a = "aaaaaaaa-0000-0000-0000-000000000001"
      b = "bbbbbbbb-0000-0000-0000-000000000002"
      assert ThreadPolicy.canonical_pair(a, b) == {a, b}
      assert ThreadPolicy.canonical_pair(b, a) == {a, b}
    end

    test "same id pair is stable" do
      id = "cccccccc-0000-0000-0000-000000000003"
      assert ThreadPolicy.canonical_pair(id, id) == {id, id}
    end
  end

  describe "can_send?/2" do
    test "returns :ok when actor is a participant" do
      actor_id = "aaaaaaaa-0000-0000-0000-000000000001"

      thread = %{
        participants: [
          %{user_id: actor_id},
          %{user_id: "bbbbbbbb-0000-0000-0000-000000000002"}
        ]
      }

      assert :ok == ThreadPolicy.can_send?(actor_id, thread)
    end

    test "returns :error when actor is not a participant" do
      actor_id = "aaaaaaaa-0000-0000-0000-000000000001"
      other_id = "cccccccc-0000-0000-0000-000000000003"

      thread = %{
        participants: [
          %{user_id: "bbbbbbbb-0000-0000-0000-000000000002"},
          %{user_id: other_id}
        ]
      }

      assert {:error, :forbidden} == ThreadPolicy.can_send?(actor_id, thread)
    end
  end

  describe "can_read?/2" do
    test "returns :ok when actor is a participant" do
      actor_id = "aaaaaaaa-0000-0000-0000-000000000001"
      thread = %{participants: [%{user_id: actor_id}]}
      assert :ok == ThreadPolicy.can_read?(actor_id, thread)
    end

    test "returns :error when actor is not a participant" do
      thread = %{participants: [%{user_id: "bbbbbbbb-0000-0000-0000-000000000002"}]}
      assert {:error, :forbidden} == ThreadPolicy.can_read?("stranger-id", thread)
    end
  end
end
