defmodule MilosTraining.Application.JournalFeed do
  @moduledoc """
  Ημερολόγιο › Ροή (ADR-139 §9): every journal entry of one member, newest
  first, paged by an opaque cursor over `(occurred_at, kind, id)`.

  Each kind is listed by the context that owns it; this module asks every
  requested source for one page after the cursor, merges them and keeps the
  newest page. The same sources answer for the member (`:owner`, in their
  personal session, across gyms) and for a coach of one gym
  (`{:coach, organization_id}`, in the coach's tenant session), where each
  source applies the ladder: only entries on a rung that reaches the coach,
  plus every injury (vision §4.5) and every review.
  """

  alias MilosTraining.Application.{JournalComments, ListWorkoutExecutions}
  alias MilosTraining.{Execution, Feedback, Journal, Pantheon, Wellbeing}

  @default_limit 30
  @max_limit 100

  @doc "Kinds in feed order of ties (the cursor compares kinds as text)."
  def kinds, do: Journal.visibility_kinds()

  @doc """
  One page: `%{items: [item], next_cursor: cursor | nil}`. Params: `cursor`,
  `kinds` (list or comma-separated) and `limit`.
  """
  def page(user_id, scope, params) do
    with {:ok, cursor} <- Journal.decode_feed_cursor(param(params, "cursor")),
         {:ok, kinds} <- requested_kinds(param(params, "kinds")) do
      limit = limit(param(params, "limit"))

      pages = Enum.map(kinds, &{&1, source(&1, user_id, cursor, limit, scope)})
      items = pages |> Enum.flat_map(&elem(&1, 1)) |> Journal.sort_feed()
      page = Enum.take(items, limit)

      more? =
        length(items) > limit or Enum.any?(pages, fn {_kind, rows} -> length(rows) == limit end)

      {:ok,
       %{
         items: page,
         next_cursor: if(more? and page != [], do: Journal.encode_feed_cursor(List.last(page)))
       }}
    end
  end

  # One source: its rows after the cursor, as feed items.
  defp source(kind, user_id, cursor, limit, scope) do
    bound = Journal.feed_bound(kind, cursor)
    kind |> rows(user_id, bound, limit, scope) |> items(kind)
  end

  defp rows("execution", user_id, bound, limit, scope),
    do: Execution.list_execution_items(user_id, bound, limit, scope)

  defp rows("training_log", user_id, bound, limit, scope),
    do: Execution.list_training_log_items(user_id, bound, limit, scope)

  defp rows("pr", user_id, bound, limit, scope),
    do: Pantheon.list_record_items(user_id, bound, limit, scope)

  defp rows("injury", user_id, bound, limit, scope),
    do: Wellbeing.list_injury_items(user_id, bound, limit, scope)

  defp rows("review", user_id, bound, limit, scope),
    do: Feedback.list_review_items(user_id, bound, limit, scope)

  defp rows("note", user_id, bound, limit, scope),
    do: Journal.list_note_items(user_id, bound, limit, scope)

  defp rows("check_in", user_id, bound, limit, scope),
    do: Wellbeing.list_check_in_items(user_id, bound, limit, scope)

  defp items(executions, "execution") do
    executions
    |> ListWorkoutExecutions.summarize()
    |> Enum.map(&Journal.feed_item("execution", &1, &1.completed_at_utc, tz: &1.completed_at_tz))
  end

  defp items(entries, "training_log") do
    entries
    |> JournalComments.attach("training_log")
    |> Enum.map(
      &Journal.feed_item("training_log", &1, &1.performed_at_utc, tz: &1.performed_at_tz)
    )
  end

  defp items(records, "pr") do
    records
    |> JournalComments.attach("pr")
    |> Enum.map(fn record ->
      on = to_date(record.beaten_on)
      Journal.feed_item("pr", record, midnight(on), on: on)
    end)
  end

  defp items(injuries, "injury"),
    do: Enum.map(injuries, &Journal.feed_item("injury", &1, &1.inserted_at))

  defp items(reviews, "review"),
    do: Enum.map(reviews, &Journal.feed_item("review", &1, utc(&1.inserted_at)))

  defp items(notes, "note"),
    do: Enum.map(notes, &Journal.feed_item("note", &1, &1.written_at, tz: &1.written_tz))

  defp items(check_ins, "check_in"),
    do:
      Enum.map(
        check_ins,
        &Journal.feed_item("check_in", &1, &1.recorded_at, tz: &1.recorded_tz)
      )

  defp midnight(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  # The PR facade serialises `beaten_on` as an ISO date.
  defp to_date(%Date{} = date), do: date
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)

  defp utc(%DateTime{} = at), do: at
  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")

  defp requested_kinds(nil), do: {:ok, kinds()}
  defp requested_kinds(""), do: {:ok, kinds()}

  defp requested_kinds(kinds) when is_binary(kinds),
    do: kinds |> String.split(",", trim: true) |> requested_kinds()

  defp requested_kinds(kinds) when is_list(kinds) do
    kinds = kinds |> Enum.map(&to_string/1) |> Enum.uniq()

    if kinds != [] and Enum.all?(kinds, &(&1 in kinds())),
      do: {:ok, kinds},
      else: {:error, :unknown_kind}
  end

  defp requested_kinds(_kinds), do: {:error, :unknown_kind}

  defp limit(nil), do: @default_limit

  defp limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {limit, ""} -> limit(limit)
      _invalid -> @default_limit
    end
  end

  defp limit(_value), do: @default_limit

  defp param(params, key),
    do: Map.get(params, key, Map.get(params, String.to_existing_atom(key)))
end
