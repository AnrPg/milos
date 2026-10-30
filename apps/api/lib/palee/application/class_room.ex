defmodule Palee.Application.ClassRoom do
  @moduledoc """
  The room of a class as the people who see the class may see it (ADR-290):
  in the class details, «📍 room» opens the floor plan on the right floor
  with the room coloured, its directions and its photos.

  Staff who see the spaces always may; members and athletes only when the
  gym shows its floor plans in classes (Settings › Spaces), and the floor
  plan only when its floor is not hidden. Cleaning points never show here.
  """

  alias Palee.Application.{SpaceDirectory, SpacePhotos}
  alias Palee.{Organizations, Scheduling, Spaces}

  @space_rights [
    :view_spaces,
    :manage_spaces,
    :edit_space_details,
    :set_space_unavailable,
    :manage_schedule
  ]
  @staff_roles [:owner, :admin, :coach]

  @doc "The room of class `slot_id`: space, floor plan (or nil), area and photos."
  def call(context, slot_id) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- visible_class(context, slot),
         %{} = space <- space_of(context, slot) || {:error, :not_found} do
      plan = space.floor_plan_id && Spaces.get_floor_plan(context, space.floor_plan_id)
      view = Spaces.class_view(Spaces.get_settings(context), plan, sees_spaces?(context))
      shown_plan = if view.plan and plan, do: plan

      if view.photos do
        {:ok,
         %{
           space: Map.take(space, [:id, :name, :description, :directions]),
           floor_plan: shown_plan && hd(SpaceDirectory.present_plans([shown_plan], context)),
           area: shown_plan && space.area,
           photos:
             SpacePhotos.present(
               context,
               :photos,
               Spaces.list_photos(context, :photos, %{space_ids: [space.id]})
             )
         }}
      else
        {:error, :forbidden}
      end
    end
  end

  @doc """
  The ids of `spaces` (maps from `Spaces.list_spaces/2`) whose room view has
  something to show this viewer: a floor plan with the room drawn on it,
  photos, a description or directions.
  """
  def viewable_ids(_context, []), do: MapSet.new()

  def viewable_ids(context, spaces) do
    settings = Spaces.get_settings(context)
    sees = sees_spaces?(context)

    if sees or settings.floor_plans_in_classes do
      plans = context |> Spaces.list_floor_plans() |> Map.new(&{&1.id, &1})

      with_photos =
        context
        |> Spaces.list_photos(:photos, %{space_ids: Enum.map(spaces, & &1.id)})
        |> MapSet.new(& &1.space_id)

      spaces
      |> Enum.filter(fn space ->
        plan = space.floor_plan_id && plans[space.floor_plan_id]
        view = Spaces.class_view(settings, plan, sees)

        (view.plan and not is_nil(plan) and not is_nil(space.area)) or
          MapSet.member?(with_photos, space.id) or
          text?(space.description) or
          text?(space.directions)
      end)
      |> MapSet.new(& &1.id)
    else
      MapSet.new()
    end
  end

  @doc "Whether the caller sees the gym's spaces (staff who plan or run them)."
  def sees_spaces?(context), do: Enum.any?(@space_rights, &Organizations.can?(context, &1))

  # Drafts (no WOD yet) are staff-only, like on the schedule (ADR-176).
  defp visible_class(context, slot) do
    cond do
      context.role in @staff_roles -> :ok
      Scheduling.class_published?(slot) -> :ok
      true -> {:error, :not_found}
    end
  end

  defp text?(value), do: is_binary(value) and String.trim(value) != ""

  defp space_of(_context, %{space_id: nil}), do: nil
  defp space_of(context, %{space_id: id}), do: Spaces.get_space(context, id)
  defp space_of(_context, _slot), do: nil
end
