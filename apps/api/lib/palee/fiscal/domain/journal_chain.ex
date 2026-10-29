defmodule Palee.Fiscal.Domain.JournalChain do
  @moduledoc """
  The hash chain of the fiscal journal (ADR-242).

  Each entry's hash is `SHA-256(previous_hash <> "\\n" <> canonical_json)`
  in lowercase hex, where the canonical JSON covers the entry's position,
  organization, event type, subject, actor, time and payload. The first
  entry of an organization chains to `genesis_hash/0`.
  """

  alias Palee.Fiscal.Domain.CanonicalJson

  @genesis String.duplicate("0", 64)

  @event_types ~w(
    identity_saved document_issued period_closed archive_exported
    journal_verified authority_connection_saved document_reported
    sales_tax_rates_saved export_settings_saved accounting_exported
    network_connection_saved document_delivered
    till_connection_saved receipt_signed till_device_failed
    document_emailed registry_connection_saved
  )

  @hashed_fields ~w(position organization_id event_type subject_type subject_id actor_id occurred_at payload)a

  def genesis_hash, do: @genesis
  def event_types, do: @event_types

  @doc "The fields of an entry that its hash covers."
  def hashed_fields, do: @hashed_fields

  @doc """
  Builds the next entry after `head` (`%{position, hash}` or nil for the
  first one): `{:ok, %{position, previous_hash, hash, ...}}`.
  """
  def next(head, %{event_type: event_type} = attrs) do
    cond do
      event_type not in @event_types ->
        {:error, :unknown_journal_event}

      not match?(%DateTime{}, attrs[:occurred_at]) ->
        {:error, :invalid_journal_time}

      true ->
        {position, previous_hash} = head_values(head)

        entry =
          @hashed_fields
          |> Map.new(&{&1, Map.get(attrs, &1)})
          |> Map.put(:position, position + 1)
          |> Map.update!(:payload, &(&1 || %{}))
          |> Map.update!(:occurred_at, &microseconds/1)

        with {:ok, payload} <- canonical_payload(entry.payload) do
          entry = %{entry | payload: payload}

          {:ok,
           Map.merge(entry, %{previous_hash: previous_hash, hash: hash(previous_hash, entry)})}
        end
    end
  end

  defp head_values(nil), do: {0, @genesis}
  defp head_values(%{position: position, hash: hash}), do: {position, hash}

  defp canonical_payload(payload) when is_map(payload) do
    {:ok, CanonicalJson.normalize(payload)}
  rescue
    ArgumentError -> {:error, :invalid_journal_payload}
  end

  defp canonical_payload(_payload), do: {:error, :invalid_journal_payload}

  @doc "The hash of an entry given the previous hash."
  def hash(previous_hash, entry) do
    # Absent and nil fields hash alike: both are `null`.
    body =
      @hashed_fields
      |> Map.new(&{&1, Map.get(entry, &1)})
      |> Map.update!(:occurred_at, &timestamp/1)
      |> CanonicalJson.encode!()

    :crypto.hash(:sha256, [previous_hash, "\n", body]) |> Base.encode16(case: :lower)
  end

  defp timestamp(%DateTime{} = at), do: at |> microseconds() |> DateTime.to_iso8601()
  defp timestamp(value), do: value

  # Always six digits, so a time read back from the database (usec precision)
  # hashes exactly like the one that was written.
  @doc false
  def microseconds(%DateTime{} = at) do
    at = DateTime.shift_zone!(at, "Etc/UTC")
    {microsecond, _precision} = at.microsecond
    %{at | microsecond: {microsecond, 6}}
  end

  @doc """
  Checks entries in position order: positions are 1..n with no gaps, each
  links to the one before and each hash matches its content. `verify_signature`
  (`fn entry -> boolean end`) checks the signature of each entry.

  `%{valid: true, entries: n, head: hash}` or
  `%{valid: false, entries: n, broken_at: position, reason: atom}`.
  """
  def verify(entries, verify_signature \\ fn _entry -> true end) do
    entries
    |> Enum.reduce_while({0, @genesis}, fn entry, {position, previous_hash} ->
      cond do
        entry.position != position + 1 ->
          {:halt, {:broken, position + 1, :position_gap}}

        entry.previous_hash != previous_hash ->
          {:halt, {:broken, entry.position, :broken_link}}

        hash(previous_hash, entry) != entry.hash ->
          {:halt, {:broken, entry.position, :hash_mismatch}}

        not verify_signature.(entry) ->
          {:halt, {:broken, entry.position, :bad_signature}}

        true ->
          {:cont, {entry.position, entry.hash}}
      end
    end)
    |> case do
      {:broken, position, reason} ->
        %{valid: false, entries: length(entries), broken_at: position, reason: reason}

      {count, head} ->
        %{valid: true, entries: count, head: head}
    end
  end
end
