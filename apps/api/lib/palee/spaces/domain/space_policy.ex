defmodule Palee.Spaces.Domain.SpacePolicy do
  @moduledoc """
  Rules of a gym's spaces (ADR-202): who may change which fields, the shape
  of a space's area on a floor plan, unavailability windows, and the
  warnings the schedule shows when two classes share a space.

  * Owners and admins (`manage_spaces`) change everything.
  * Front desk (`edit_space_details`) changes the name, description and
    directions only.
  * An area is a polygon of 3 to 32 points in normalized floor-plan
    coordinates (`0..1` on both axes, origin top-left), so it scales with
    the image. A rectangle is four points.
  * A class may not take place in a space while the space is unavailable
    (`space_unavailable`); two classes overlapping in one space are only a
    warning, since a big room can be shared on purpose.
  """

  @detail_fields ~w(name description directions)a
  @manager_fields @detail_fields ++ ~w(location_id tasks floor_plan_id area)a

  @min_points 3
  @max_points 32

  @type window :: %{starts_at: DateTime.t(), ends_at: DateTime.t()}

  @doc "Fields a holder of `:manage` or `:details` rights may change."
  def editable_fields(:manage), do: @manager_fields
  def editable_fields(:details), do: @detail_fields

  @doc "`:ok` when params change only fields of `rights` (atom or string keys)."
  def check_fields(params, rights) when is_map(params) do
    allowed = rights |> editable_fields() |> Enum.flat_map(&[&1, Atom.to_string(&1)])

    if params |> Map.keys() |> Enum.all?(&(&1 in allowed)),
      do: :ok,
      else: {:error, :forbidden}
  end

  @doc "Validates an area and returns it rounded, as `%{\"points\" => [[x, y], ...]}`."
  def normalize_area(nil), do: {:ok, nil}

  def normalize_area(%{} = area) do
    points = Map.get(area, "points") || Map.get(area, :points)

    with true <- is_list(points) || :error,
         count = length(points),
         true <- (count >= @min_points and count <= @max_points) || :error,
         {:ok, points} <- normalize_points(points) do
      {:ok, %{"points" => points}}
    else
      _invalid -> {:error, :invalid_space_area}
    end
  end

  def normalize_area(_area), do: {:error, :invalid_space_area}

  defp normalize_points(points) do
    Enum.reduce_while(points, {:ok, []}, fn point, {:ok, acc} ->
      case point do
        [x, y] when is_number(x) and is_number(y) and x >= 0 and x <= 1 and y >= 0 and y <= 1 ->
          {:cont, {:ok, [[round4(x), round4(y)] | acc]}}

        _invalid ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, points} -> {:ok, Enum.reverse(points)}
      error -> error
    end
  end

  defp round4(value), do: Float.round(value / 1, 4)

  @doc "A rectangle (x, y, width, height, all normalized) as an area."
  def rectangle(x, y, width, height),
    do: %{"points" => [[x, y], [x + width, y], [x + width, y + height], [x, y + height]]}

  @doc "`:ok` when an unavailability window ends after it starts."
  def validate_window(%DateTime{} = starts_at, %DateTime{} = ends_at) do
    if DateTime.compare(ends_at, starts_at) == :gt,
      do: :ok,
      else: {:error, :invalid_unavailability}
  end

  def validate_window(_starts_at, _ends_at), do: {:error, :invalid_unavailability}

  @doc "Whether `[a_start, a_end)` and `[b_start, b_end)` overlap."
  def overlap?(a_start, a_end, b_start, b_end),
    do: DateTime.compare(a_start, b_end) == :lt and DateTime.compare(b_start, a_end) == :lt

  @doc "The first window that overlaps a class at `starts_at` for `duration_minutes`, or nil."
  def blocking_window(windows, %DateTime{} = starts_at, duration_minutes)
      when is_integer(duration_minutes) do
    ends_at = DateTime.add(starts_at, duration_minutes * 60, :second)

    windows
    |> Enum.sort_by(& &1.starts_at, DateTime)
    |> Enum.find(&overlap?(&1.starts_at, &1.ends_at, starts_at, ends_at))
  end

  @doc """
  `:ok`, or `{:error, {:space_unavailable, window}}` when the class would run
  while the space is unavailable.
  """
  def check_available(windows, starts_at, duration_minutes) do
    case blocking_window(windows, starts_at, duration_minutes) do
      nil -> :ok
      window -> {:error, {:space_unavailable, window}}
    end
  end

  @doc """
  The ids of classes that overlap another class in the same space. Classes
  are maps with `id`, `space_id`, `scheduled_at` and `duration_minutes`;
  classes without a space never overlap.
  """
  def overlapping_ids(classes) do
    classes
    |> Enum.reject(&is_nil(Map.get(&1, :space_id)))
    |> Enum.group_by(& &1.space_id)
    |> Enum.flat_map(fn {_space, list} -> overlapping_in_space(list) end)
    |> MapSet.new()
  end

  defp overlapping_in_space(list) do
    sorted = Enum.sort_by(list, & &1.scheduled_at, DateTime)

    for a <- sorted,
        b <- sorted,
        a.id != b.id,
        overlap?(a.scheduled_at, ends_at(a), b.scheduled_at, ends_at(b)),
        uniq: true,
        do: a.id
  end

  @doc "When a class ends."
  def ends_at(%{scheduled_at: starts_at, duration_minutes: minutes}),
    do: DateTime.add(starts_at, (minutes || 0) * 60, :second)

  @doc "Whether a space can hold classes: it exists and is not archived."
  def usable(%{archived_at: nil}), do: :ok
  def usable(%{}), do: {:error, :space_archived}
  def usable(nil), do: {:error, :space_not_found}

  @doc "A space belongs to the class's branch (both may be nil: a gym without branches)."
  def same_branch(%{location_id: location_id}, location_id), do: :ok
  def same_branch(%{location_id: nil}, _class_location), do: :ok
  def same_branch(_space, _class_location), do: {:error, :space_wrong_branch}

  @doc "Trims text; blank becomes nil."
  def blank_to_nil(nil), do: nil

  def blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  def blank_to_nil(value), do: value
end
