defmodule Palee.Fiscal.Domain.JournalChainTest do
  use ExUnit.Case, async: true

  alias Palee.Fiscal.Domain.{CanonicalJson, JournalChain}

  @org "7b0c6b4e-2f61-4a73-9a8f-1b1d3b2f0c11"

  defp attrs(n),
    do: %{
      organization_id: @org,
      event_type: "document_issued",
      subject_type: "fiscal_document",
      occurred_at: DateTime.add(~U[2027-02-01 10:00:00Z], n, :second),
      payload: %{number: "R-00000#{n}", gross_cents: n * 100}
    }

  defp chain(count) do
    {entries, _head} =
      Enum.map_reduce(1..count, nil, fn n, head ->
        {:ok, entry} = JournalChain.next(head, attrs(n))
        {entry, entry}
      end)

    entries
  end

  test "canonical JSON sorts keys, has no spaces and refuses floats" do
    assert CanonicalJson.encode!(%{b: 1, a: [true, nil, "é"]}) == ~s({"a":[true,null,"é"],"b":1})
    assert {:error, :not_canonical} = CanonicalJson.encode(%{a: 1.5})
    assert CanonicalJson.encode!(%{d: ~D[2027-02-01]}) == ~s({"d":"2027-02-01"})
  end

  test "the first entry chains to the genesis hash and positions are gapless" do
    [first, second, third] = chain(3)
    assert first.previous_hash == JournalChain.genesis_hash()
    assert first.position == 1 and second.position == 2 and third.position == 3
    assert second.previous_hash == first.hash
    assert %{valid: true, entries: 3, head: head} = JournalChain.verify(chain(3))
    assert head == third.hash
  end

  test "timestamps hash the same at any precision" do
    {:ok, a} = JournalChain.next(nil, %{attrs(1) | occurred_at: ~U[2027-02-01 10:00:01Z]})
    {:ok, b} = JournalChain.next(nil, %{attrs(1) | occurred_at: ~U[2027-02-01 10:00:01.000000Z]})
    assert a.hash == b.hash
  end

  test "any edit, deletion or reordering is detected" do
    entries = chain(4)

    edited = List.update_at(entries, 1, &put_in(&1.payload["gross_cents"], 1))
    assert %{valid: false, broken_at: 2, reason: :hash_mismatch} = JournalChain.verify(edited)

    deleted = List.delete_at(entries, 2)
    assert %{valid: false, broken_at: 3, reason: :position_gap} = JournalChain.verify(deleted)

    relinked = List.update_at(entries, 2, &%{&1 | previous_hash: String.duplicate("a", 64)})
    assert %{valid: false, broken_at: 3, reason: :broken_link} = JournalChain.verify(relinked)

    assert %{valid: false, broken_at: 1, reason: :bad_signature} =
             JournalChain.verify(entries, fn _ -> false end)
  end

  test "unknown events and bad payloads are refused" do
    assert {:error, :unknown_journal_event} =
             JournalChain.next(nil, %{attrs(1) | event_type: "x"})

    assert {:error, :invalid_journal_payload} =
             JournalChain.next(nil, %{attrs(1) | payload: %{a: 1.5}})
  end
end
