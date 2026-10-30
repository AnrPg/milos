defmodule Palee.Spaces.Domain.PhotoPolicy do
  @moduledoc """
  Rules of the photos of a room (ADR-290).

  * A room has photos (to get an idea of it) and cleaning points (a photo of
    a part of the room and what to clean there). They are separate lists, so
    a close-up made for the janitor never shows up for members by mistake.
  * Each list holds at most 30 entries, like a room's task checklist.
  * A room photo starts off the public box page; its uploader turns it on.
  * Who sees a class sees the room's photos, and the floor plan with its
    room coloured, only when the gym shows its floor plans in classes; a
    hidden floor keeps its plan back. Staff who see the spaces see both.
  """

  @max_per_space 30

  def max_per_space, do: @max_per_space

  @doc "`:ok` while a room has room for one more photo or point."
  def check_room(count) when count < @max_per_space, do: :ok
  def check_room(_count), do: {:error, :space_photos_full}

  @doc """
  Orders by the given ids: listed ids first, in that order, then the rest in
  their current order. Returns `[{id, sort_order}]` for every entry.
  """
  def reorder(entries, ids) when is_list(ids) do
    known = MapSet.new(entries, & &1.id)
    listed = ids |> Enum.uniq() |> Enum.filter(&MapSet.member?(known, &1))
    rest = entries |> Enum.map(& &1.id) |> Enum.reject(&(&1 in listed))

    (listed ++ rest) |> Enum.with_index() |> Enum.map(fn {id, index} -> {id, index} end)
  end

  @doc """
  What the viewer of a class may see of its room besides its name:
  `%{plan: boolean, photos: boolean}`. Staff who see the spaces see both;
  everyone else only when the gym shows its floor plans in classes, and the
  floor plan only when its floor is not hidden.
  """
  def class_view(_settings, _plan, true = _sees_spaces), do: %{plan: true, photos: true}

  def class_view(%{floor_plans_in_classes: true}, plan, _sees_spaces),
    do: %{plan: match?(%{shown_in_classes: true}, plan), photos: true}

  def class_view(_settings, _plan, _sees_spaces), do: %{plan: false, photos: false}
end
