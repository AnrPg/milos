defmodule Palee.Application.WorkoutChoices do
  @moduledoc """
  What the class form offers when a coach picks a WOD.

  A library can hold thousands of WODs, so the form never loads it whole:
  `suggested/2` gives the few a coach most likely wants (the WOD other classes
  already use that gym day, the ones recently used for this class type, the
  newest), and `search/2` finds the rest by title words, type and folder,
  a page at a time.
  """

  alias Palee.{Organizations, Scheduling, Workouts}
  alias Palee.TimeZones.ZonedTime

  @page 20
  @recent_days 60
  @per_group 5

  def search(%{organization_id: _} = context, params) do
    limit = params |> param(:limit) |> to_int(@page) |> min(50) |> max(1)
    offset = params |> param(:offset) |> to_int(0) |> max(0)

    %{workouts: workouts, has_more: has_more} =
      Workouts.search_workout_choices(context,
        query: blank_to_nil(param(params, :q)),
        type: blank_to_nil(param(params, :type)),
        folder_id: blank_to_nil(param(params, :folder_id)),
        limit: limit,
        offset: offset
      )

    {:ok,
     %{
       workouts: workouts,
       has_more: has_more,
       next_offset: if(has_more, do: offset + length(workouts), else: nil)
     }}
  end

  def suggested(%{organization_id: organization_id} = context, params) do
    zone = Organizations.organization_timezone(organization_id)

    with {:ok, date} <- parse_date(param(params, :date), zone) do
      day_start = ZonedTime.start_of_day(date, zone)
      day_end = ZonedTime.start_of_day(Date.add(date, 1), zone)
      class_type_id = blank_to_nil(param(params, :class_type_id))

      same_day_ids = usage_ids(context, day_start, day_end, [])

      recent_ids =
        context
        |> usage_ids(DateTime.add(day_start, -@recent_days * 86_400, :second), day_start,
          class_type_id: class_type_id
        )
        |> Kernel.--(same_day_ids)

      same_day = Workouts.workout_choices_by_ids(context, same_day_ids)
      recent = context |> Workouts.workout_choices_by_ids(recent_ids) |> Enum.take(@per_group)
      shown = MapSet.new(same_day ++ recent, & &1.id)

      %{workouts: latest} = Workouts.search_workout_choices(context, limit: @per_group * 2)
      newest = latest |> Enum.reject(&MapSet.member?(shown, &1.id)) |> Enum.take(3)

      {:ok, %{date: date, same_day: same_day, recent: recent, newest: newest}}
    end
  end

  defp usage_ids(context, from, to, opts) do
    context
    |> Scheduling.class_workout_usage(from, to, Keyword.put(opts, :limit, @per_group * 2))
    |> Enum.map(& &1.workout_id)
  end

  defp parse_date(nil, zone), do: {:ok, ZonedTime.local_date(DateTime.utc_now(), zone)}

  defp parse_date(value, _zone) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date(_value, _zone), do: {:error, :invalid_date}

  defp param(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp to_int(value, _default) when is_integer(value), do: value

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp to_int(_value, default), do: default

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil
end
