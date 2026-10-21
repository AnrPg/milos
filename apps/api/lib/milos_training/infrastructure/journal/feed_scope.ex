defmodule MilosTraining.Infrastructure.Journal.FeedScope do
  @moduledoc """
  Whose entries one journal source lists (ADR-139 §6, §9; ADR-162).

  * `:owner` — the member's own, in the member's session, across providers.
  * `{:owner, query}` — the same, narrowed by a Ροή filter
    (`JournalFilter.to_query/1`): sources, rungs, a date window and text.
  * `{:coach, organization_id}` — what a coach of one provider may read:
    entries recorded there on a rung that reaches the coach, plus (ADR-162)
    entries of shareable kinds the member shared with the acting coach there
    (`milos_journal_entry_shared_with_coach`, the SQL twin of
    `Journal.Domain.CoachAudience`). Kinds the coach always sees (injuries)
    or that are a rung of their own (reviews) pass `rung?: false`.

  Options each source passes: `kind` (its feed kind), `at` (the timestamp
  field, or `{:date, field}` for day-dated entries), `text` (its own text
  fields), `text_exists` (`:comments` or `:check_in_answers`), `device` (the
  field naming a device source) and `visibility` (`{:fixed, rung}` for
  kinds without a ladder column).
  """

  import Ecto.Query

  alias MilosTraining.Journal.Domain.{CoachAudience, EntrySource}

  def apply(query, user_id, scope, opts \\ [])

  def apply(query, user_id, :owner, _opts), do: where(query, [row], row.user_id == ^user_id)

  def apply(query, user_id, {:owner, filter}, opts) when is_map(filter) do
    query
    |> where([row], row.user_id == ^user_id)
    |> sources(filter, opts)
    |> visibilities(filter, opts)
    |> window(filter, opts)
    |> text(filter, opts)
  end

  def apply(query, user_id, {:coach, organization_id}, opts) do
    query = where(query, [row], row.user_id == ^user_id)

    if Keyword.get(opts, :rung?, true) do
      query
      |> home_or_shared(organization_id, Keyword.get(opts, :kind))
      |> where(
        [row],
        fragment("milos_journal_visibility_reaches_coach(?)", row.journal_visibility)
      )
    else
      where(query, [row], row.organization_id == ^organization_id)
    end
  end

  defp home_or_shared(query, organization_id, kind) do
    if CoachAudience.shareable?(kind) do
      where(
        query,
        [row],
        row.organization_id == ^organization_id or
          fragment(
            "milos_journal_entry_shared_with_coach(?, ?, ?, ?, ?, NULLIF(current_setting('app.user_id', true), '')::uuid)",
            ^kind,
            row.id,
            row.user_id,
            row.organization_id,
            type(^organization_id, :binary_id)
          )
      )
    else
      where(query, [row], row.organization_id == ^organization_id)
    end
  end

  # ------------------------------------------------------------ owner filter

  defp sources(query, %{sources?: false}, _opts), do: query

  defp sources(query, filter, opts) do
    device = device_dynamic(Keyword.get(opts, :device))
    organizations = filter.organization_ids

    by_org =
      if organizations == [],
        do: dynamic(false),
        else: dynamic([row], row.organization_id in type(^organizations, {:array, :binary_id}))

    by_org = if device == false, do: by_org, else: dynamic([row], ^by_org and not (^device))

    freeform =
      cond do
        not filter.freeform? -> dynamic(false)
        device == false -> dynamic([row], is_nil(row.organization_id))
        true -> dynamic([row], is_nil(row.organization_id) and not (^device))
      end

    devices = if filter.device? and device != false, do: device, else: dynamic(false)

    where(query, ^dynamic(^by_org or ^freeform or ^devices))
  end

  defp device_dynamic(nil), do: false

  defp device_dynamic(field) do
    sources = EntrySource.device_sources()
    dynamic([row], fragment("coalesce(?, '') = ANY(?)", field(row, ^field), ^sources))
  end

  defp visibilities(query, %{visibilities: []}, _opts), do: query

  defp visibilities(query, %{visibilities: rungs}, opts) do
    case Keyword.get(opts, :visibility) do
      {:fixed, rung} -> if rung in rungs, do: query, else: where(query, false)
      _column -> where(query, [row], row.journal_visibility in ^rungs)
    end
  end

  defp window(query, %{from: nil, to: nil}, _opts), do: query

  defp window(query, filter, opts) do
    case Keyword.get(opts, :at) do
      nil -> query
      {:date, field} -> date_window(query, field, filter)
      field -> time_window(query, field, filter)
    end
  end

  defp time_window(query, field, filter) do
    query
    |> then(&if(filter.from, do: where(&1, [row], field(row, ^field) >= ^filter.from), else: &1))
    |> then(&if(filter.to, do: where(&1, [row], field(row, ^field) < ^filter.to), else: &1))
  end

  defp date_window(query, field, %{from_date: from, to_date: to}) do
    query
    |> then(&if(from, do: where(&1, [row], field(row, ^field) >= ^from), else: &1))
    |> then(&if(to, do: where(&1, [row], field(row, ^field) < ^to), else: &1))
  end

  defp text(query, %{q: nil}, _opts), do: query

  defp text(query, %{q: pattern}, opts) do
    own =
      opts
      |> Keyword.get(:text, [])
      |> Enum.reduce(dynamic(false), fn field, acc ->
        dynamic([row], ^acc or ilike(field(row, ^field), ^pattern))
      end)

    matched =
      case {Keyword.get(opts, :text_exists), Keyword.get(opts, :kind)} do
        {:comments, kind} when is_binary(kind) ->
          dynamic(
            [row],
            ^own or
              fragment(
                "EXISTS (SELECT 1 FROM journal_comments c WHERE c.entry_kind = ? AND c.entry_id = ? AND c.deleted_at IS NULL AND c.body ILIKE ?)",
                ^kind,
                row.id,
                ^pattern
              )
          )

        {:check_in_answers, _kind} ->
          dynamic(
            [row],
            ^own or
              fragment(
                "EXISTS (SELECT 1 FROM wellbeing_check_in_answers a WHERE a.check_in_id = ? AND a.note ILIKE ?)",
                row.id,
                ^pattern
              )
          )

        _none ->
          own
      end

    where(query, ^matched)
  end
end
