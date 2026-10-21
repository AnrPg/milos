defmodule MilosTraining.Application.GetAccountHistory do
  @moduledoc """
  `GET /api/me/history` (ADR-150, ADR-162): the member's training log across
  every provider, newest first, paged by `offset`/`limit`.

  * `workouts` — every workout they did or started, at any provider or on
    their own, read in their personal session.
  * `classes` — the classes they booked and that took place, at every
    provider they are or were a member of. A booking is the provider's
    record of the member's own visit, so it is read in that provider's
    scope (also after the membership ended: the history stays theirs).

  Each entry carries its `source` (`organization` with `former`,
  `freeform`, `device`); `sources`, `date_from` and `date_to` filter.
  `/api/org/:slug/me/history` keeps its per-provider shape.
  """

  alias MilosTraining.Application.AccountTraining
  alias MilosTraining.Identity.Domain.FilterFields
  alias MilosTraining.{Journal, Organizations, Scheduling}

  @default_limit 10
  @max_limit 50

  def call(context, params) do
    params = FilterFields.stringify(params)
    limit = params["limit"] |> to_int(@default_limit) |> min(@max_limit) |> max(1)
    offset = params["offset"] |> to_int(0) |> max(0)

    with {:ok, sources} <- FilterFields.sources(:sources, params["sources"]),
         {:ok, {from, to}} <- FilterFields.date_range(params["date_from"], params["date_to"]) do
      filter = %{sources: sources, from: from, to: to}

      case params["kind"] || "workouts" do
        "workouts" -> {:ok, page("workouts", workouts(context, filter), offset, limit)}
        "classes" -> {:ok, page("classes", classes(context, filter, offset + limit), offset, limit)}
        _other -> {:error, :invalid_history_kind}
      end
    end
  end

  defp page(kind, {entries, total}, offset, limit) do
    %{
      kind: kind,
      total: total,
      offset: offset,
      next_offset: if(offset + limit < total, do: offset + limit),
      entries: entries |> Enum.drop(offset) |> Enum.take(limit)
    }
  end

  defp workouts(context, filter) do
    entries =
      context
      |> AccountTraining.load()
      |> Map.fetch!(:executions)
      |> Enum.filter(&keep?(filter, &1.source_label, &1.started_at_utc))
      |> Enum.sort_by(& &1.started_at_utc, {:desc, DateTime})
      |> Enum.map(fn execution ->
        %{
          id: execution.id,
          occurred_at: execution.started_at_utc,
          execution_source: to_string(execution.source),
          source: execution.source_label,
          workout: %{
            id: execution.master_workout_id,
            title: execution.workout_title,
            type: execution.workout_type && to_string(execution.workout_type)
          },
          performance: %{
            execution_id: execution.id,
            status: execution.status,
            started_at: execution.started_at_utc,
            completed_at: execution.completed_at_utc,
            elapsed_ms: execution.total_elapsed_ms,
            scale_level_slug: execution.scale_level_slug,
            scores:
              Enum.map(execution.section_scores || [], fn score ->
                %{
                  section_id: field(score, :section_id),
                  section_name: field(score, :section_name),
                  value: field(score, :value),
                  unit: field(score, :unit)
                }
              end)
          }
        }
      end)

    {entries, length(entries)}
  end

  # Each provider answers up to `needed` of its newest classes; merging them
  # newest first gives the page, and the totals add up.
  defp classes(context, filter, needed) do
    providers = Organizations.list_my_providers(context)
    directory = Organizations.provider_directory(providers)

    results =
      providers
      |> Enum.filter(&wanted?(filter.sources, &1.organization_id))
      |> Enum.map(&provider_classes(&1, context.user_id, directory, filter, needed))

    entries =
      results
      |> Enum.flat_map(&elem(&1, 0))
      |> Enum.sort_by(& &1.occurred_at, {:desc, DateTime})

    {entries, results |> Enum.map(&elem(&1, 1)) |> Enum.sum()}
  end

  defp provider_classes(provider, user_id, directory, filter, needed) do
    case Organizations.resolve_system_tenant_context(provider.organization_id, :member_history) do
      {:ok, tenant} ->
        dated? = filter.from || filter.to
        limit = if dated?, do: 1_000, else: needed

        %{entries: bookings, total: total} =
          Scheduling.list_class_history(tenant, user_id, %{limit: limit, offset: 0})

        source = Journal.entry_source(provider.organization_id, nil, directory)

        entries =
          bookings
          |> Enum.filter(&keep?(%{filter | sources: []}, source, &1.scheduled_at))
          |> Enum.map(fn booking ->
            %{
              id: booking.booking_id,
              occurred_at: booking.scheduled_at,
              source: source,
              class: %{
                name: booking.class_name,
                type_name: booking.class_type_name,
                duration_minutes: booking.duration_minutes,
                attendance: booking.attendance_status && to_string(booking.attendance_status)
              }
            }
          end)

        {entries, if(dated?, do: length(entries), else: total)}

      _closed ->
        {[], 0}
    end
  end

  defp wanted?([], _organization_id), do: true
  defp wanted?(sources, organization_id), do: organization_id in sources

  defp keep?(filter, source, at) do
    on = at && DateTime.to_date(at)

    (filter.sources == [] or AccountTraining.token(source) in filter.sources) and
      (is_nil(filter.from) or (on != nil and Date.compare(on, filter.from) != :lt)) and
      (is_nil(filter.to) or (on != nil and Date.compare(on, filter.to) != :gt))
  end

  defp to_int(nil, default), do: default
  defp to_int(value, _default) when is_integer(value), do: value

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _other -> default
    end
  end

  defp to_int(_value, default), do: default

  defp field(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
