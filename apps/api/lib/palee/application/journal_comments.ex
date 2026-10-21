defmodule Palee.Application.JournalComments do
  @moduledoc """
  Σχόλια (ADR-140 §1): the one write path for text a member puts on their own
  execution, training-log entry or PR, from any surface (the execution
  NoteModal, the FinishWizard, Καταγραφή, the PR form, the entry card).

  A save is an idempotent upsert by the client's comment id, so an offline
  client can replay it. A structured change (the modification-patch shape)
  is normalized by the Execution context and upserted by its patch id; its
  own `note` becomes the comment's text when no text is given. The comment
  takes the entry's gym; only the entry's owner may comment on it. A save is
  pushed to the member's other devices; coaches are not notified (the
  entry's rung decides whether they can read it).
  """

  alias Palee.Application.BroadcastUserSync
  alias Palee.{Execution, Journal}

  @max_batch 200

  def save(context, comment_id, params, now \\ DateTime.utc_now()) do
    with {:ok, [comment]} <- save_many(context, [Map.put(params, "id", comment_id)], now),
         do: {:ok, comment}
  end

  @doc "Saves several comments in one transaction (the FinishWizard, a log or PR form)."
  def save_many(context, comments, now \\ DateTime.utc_now())

  def save_many(%{user_id: user_id} = context, comments, now)
      when is_list(comments) and length(comments) <= @max_batch do
    Journal.with_context(context, fn ->
      Journal.transaction(fn ->
        comments
        |> Enum.reduce_while({:ok, []}, fn params, {:ok, saved} ->
          case save_one(user_id, params, now) do
            {:ok, comment} -> {:cont, {:ok, [comment | saved]}}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
        |> case do
          {:ok, saved} -> {:ok, Enum.reverse(saved)}
          error -> error
        end
      end)
    end)
    |> tap(fn
      {:ok, saved} -> Enum.each(saved, &broadcast/1)
      _error -> :ok
    end)
  end

  def save_many(_context, _comments, _now), do: {:error, :bad_request}

  def delete(%{user_id: user_id} = context, comment_id, now \\ DateTime.utc_now()) do
    with {:ok, comment} <-
           Journal.with_context(context, fn ->
             Journal.delete_comment(comment_id, user_id, now)
           end) do
      broadcast(Map.put(comment, :deleted, true))
      :ok
    end
  end

  @doc """
  Inline comments of an entry created in the same request (a training-log
  entry or a PR): the entry kind and id come from the entry, not the client.
  """
  def save_for_entry(context, entry_kind, entry_id, comments, now \\ DateTime.utc_now())

  def save_for_entry(_context, _entry_kind, _entry_id, comments, _now)
      when comments in [nil, []],
      do: {:ok, []}

  def save_for_entry(context, entry_kind, entry_id, comments, now) when is_list(comments) do
    comments
    |> Jason.encode!()
    |> Jason.decode!()
    |> Enum.map(&Map.merge(&1, %{"entry_kind" => entry_kind, "entry_id" => entry_id}))
    |> then(&save_many(context, &1, now))
  end

  def save_for_entry(_context, _entry_kind, _entry_id, _comments, _now),
    do: {:error, :bad_request}

  @doc """
  Runs `write` (returning `{:ok, entry}`) and saves the comments sent with
  it in one transaction, so an entry is never kept without the text written
  with it. Returns the entry with its comments.
  """
  def write_with_comments(context, entry_kind, comments, write, now \\ DateTime.utc_now())
      when is_function(write, 0) do
    Journal.transaction(fn ->
      with {:ok, entry} <- write.(),
           {:ok, _saved} <- save_for_entry(context, entry_kind, entry.id, comments, now) do
        {:ok, Journal.with_context(context, fn -> attach(entry, entry_kind) end)}
      end
    end)
  end

  @doc """
  Puts each entry's comments under `:comments`, oldest first. Runs in the
  caller's DB scope: the owner reads all of them, a coach only those of
  entries whose rung reaches them (RLS).
  """
  def attach(entries, entry_kind) when is_list(entries) do
    by_entry = Journal.comments_by_entry(entry_kind, Enum.map(entries, & &1.id))
    Enum.map(entries, &Map.put(&1, :comments, Map.get(by_entry, &1.id, [])))
  end

  def attach(%{id: _id} = entry, entry_kind), do: [entry] |> attach(entry_kind) |> hd()

  defp save_one(user_id, params, now) when is_map(params) do
    params = stringify(params)

    with {:ok, kind} <- entry_kind(params["entry_kind"]),
         %{user_id: ^user_id, organization_id: organization_id} <-
           Journal.comment_entry_owner(kind, params["entry_id"]) || {:error, :not_found},
         {:ok, change, change_note} <- normalize_change(params["change"]) do
      Journal.save_comment(%{
        id: params["id"],
        user_id: user_id,
        organization_id: organization_id,
        entry_kind: kind,
        entry_id: params["entry_id"],
        section_id: params["section_id"],
        exercise_id: params["exercise_id"],
        selected_text: params["selected_text"],
        selection_start: params["selection_start"],
        selection_end: params["selection_end"],
        tags: params["tags"] || [],
        body: blank_to_nil(params["body"]) || change_note,
        change: change,
        written_at: written_at(params["written_at"], now)
      })
    else
      %{user_id: _other} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp save_one(_user_id, _params, _now), do: {:error, :bad_request}

  defp entry_kind(kind) do
    if kind in Journal.comment_entry_kinds(), do: {:ok, kind}, else: {:error, :bad_request}
  end

  defp normalize_change(nil), do: {:ok, nil, nil}

  defp normalize_change(patch) when is_map(patch) do
    with {:ok, normalized} <- Execution.normalize_modification(patch),
         do: {:ok, Map.delete(normalized, "note"), normalized["note"]}
  end

  defp normalize_change(_patch), do: {:error, :bad_request}

  # The client's time (offline writes keep when they were written), never
  # in the future.
  defp written_at(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> if DateTime.compare(at, now) == :gt, do: now, else: at
      _invalid -> now
    end
  end

  defp written_at(_value, now), do: now

  # Only the owner's devices hear about it: staff may sit on the
  # execution's channel, and the entry's rung, not a push, decides what a
  # coach reads.
  defp broadcast(comment) do
    BroadcastUserSync.for_user(comment.user_id, ["journal_comments"],
      reason: "comment_saved",
      payload: %{
        entry_kind: comment.entry_kind,
        entry_id: comment.entry_id,
        comment_id: comment.id,
        deleted: Map.get(comment, :deleted, false)
      }
    )
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil
end
