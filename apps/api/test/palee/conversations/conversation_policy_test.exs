defmodule Palee.Conversations.Domain.ConversationPolicyTest do
  @moduledoc "ADR-193 §3: where a person's message lands and what each side may do."

  use ExUnit.Case, async: true

  alias Palee.Conversations.Domain.ConversationPolicy, as: P

  @a "00000000-0000-0000-0000-00000000000a"
  @b "00000000-0000-0000-0000-00000000000b"
  @now ~U[2026-10-24 07:00:00.000000Z]

  defp conversation(attrs \\ %{}) do
    Map.merge(
      %{
        id: "c",
        user_a_id: @a,
        user_b_id: @b,
        started_by_id: @a,
        a_folder: "inbox",
        b_folder: "requests",
        a_read_at: nil,
        b_read_at: nil,
        last_message_at: nil,
        last_author_id: nil
      },
      attrs
    )
  end

  test "the pair is stored in order and each side knows its fields" do
    assert P.pair(@b, @a) == {@a, @b}
    assert P.side(conversation(), @b) == :b
    assert P.other(conversation(), @a) == @b
    assert P.folder(conversation(), @b) == "requests"
    assert P.side(conversation(), "someone") == nil
  end

  test "Buddies, a shared club or a follower of the sender reach the inbox; anyone else requests" do
    assert P.new_folders(@a, @b, %{i_follow: true, follows_me: true}) == {"inbox", "inbox"}
    assert P.new_folders(@a, @b, %{shares_club: true}) == {"inbox", "inbox"}
    assert P.new_folders(@b, @a, %{follows_me: true}) == {"inbox", "inbox"}
    assert P.new_folders(@a, @b, %{i_follow: true}) == {"inbox", "requests"}
    assert P.new_folders(@b, @a, %{}) == {"requests", "inbox"}
    assert P.buddies?(%{i_follow: true, follows_me: true})
    refute P.buddies?(%{i_follow: true})
  end

  test "replying accepts a request; a decline holds unless the relationship now qualifies" do
    reply = P.after_message(conversation(), @b, %{}, @now)
    assert reply.b_folder == "inbox"
    assert reply.a_folder == "inbox"
    assert reply.b_read_at == @now
    assert reply.last_author_id == @b

    declined = conversation(%{b_folder: "declined"})
    assert P.after_message(declined, @a, %{}, @now).b_folder == "declined"
    assert P.after_message(declined, @a, %{follows_me: true}, @now).b_folder == "inbox"
    assert P.after_message(conversation(), @a, %{}, @now).b_folder == "requests"
  end

  test "only a request can be declined, by its recipient" do
    assert {:ok, %{b_folder: "declined"}} = P.decline(conversation(), @b)
    assert {:error, :not_a_request} = P.decline(conversation(), @a)
    assert P.accept(conversation(), @b) == %{b_folder: "inbox"}
  end

  test "unread and listed" do
    sent = conversation(%{last_message_at: @now, last_author_id: @a})
    assert P.unread?(sent, @b)
    refute P.unread?(sent, @a)
    refute P.unread?(%{sent | b_read_at: @now}, @b)
    refute P.listed?(conversation(), @b)
    assert P.listed?(conversation(), @a)
    assert P.listed?(sent, @b)
    refute P.listed?(%{sent | b_folder: "declined"}, @b)
  end

  test "bodies and cursors" do
    assert {:ok, "hi"} = P.normalize_body("  hi ")
    assert {:error, :message_body_required} = P.normalize_body("   ")
    assert {:error, :message_too_long_body} = P.normalize_body(String.duplicate("x", 2001))
    cursor = P.encode_cursor(@now, @a)
    assert {:ok, {@now, @a}} = P.decode_cursor(cursor)
    assert {:error, :invalid_cursor} = P.decode_cursor("nope")
  end
end
