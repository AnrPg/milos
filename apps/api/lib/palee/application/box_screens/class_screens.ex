defmodule Palee.Application.BoxScreens.ClassScreens do
  @moduledoc """
  «Στην οθόνη» on a class timer's remote (ADR-253, update 2026-10-29): the
  coach running a class pins its timer, leaderboard or WOD on a box screen
  and returns the screen to automatic, without the settings page.

  Who may is `BoxScreens.Domain.ClassScreenPolicy`: the class's own coach,
  today, on a screen of the class's branch or the whole box; staff who
  manage screens (`manage_settings` or `manage_locations`) as on Staff ›
  Box screens. A coach of another class is refused. The pin always names
  the class (`slot_id`), so it ends with the class's day.
  """

  alias Palee.{BoxScreens, Organizations, Scheduling}
  alias Palee.Application.BoxScreens.{BoxScreenToday, ScreenPresenter}
  alias Palee.TimeZones.ZonedTime

  @doc """
  The screens the person may change for class `slot_id`, with what each
  shows: `{:ok, %{screens, views}}`, or `{:error, :forbidden | :not_found}`.
  """
  def list(context, slot_id) do
    now = BoxScreens.now()

    with {:ok, class, today} <- load(context, slot_id, now) do
      actor = actor(context)

      case BoxScreens.class_screens(actor, class, BoxScreens.list(context), today) do
        [] ->
          if allowed?(actor, class, today),
            do: {:ok, %{screens: [], views: BoxScreens.class_views(actor)}},
            else: {:error, :forbidden}

        screens ->
          names = ScreenPresenter.names(Enum.map(screens, & &1.focus_changed_by_id))

          {:ok,
           %{
             screens: Enum.map(screens, &ScreenPresenter.view(&1, names, now)),
             views: BoxScreens.class_views(actor)
           }}
      end
    end
  end

  @doc "Pins `view` of class `slot_id` on screen `screen_id` (optionally `until`)."
  def pin(context, slot_id, screen_id, params) do
    now = BoxScreens.now()
    view = param(params, :view)

    with {:ok, class, today} <- load(context, slot_id, now),
         {:ok, screen} <- screen(context, screen_id),
         :ok <- BoxScreens.may_pin_class?(actor(context), class, screen, view, today),
         {:ok, screen} <-
           BoxScreens.set_override(
             context,
             screen.id,
             %{view: view, slot_id: class.id, until: param(params, :until)},
             BoxScreenToday.slot_ids(context, screen, now),
             context.user_id,
             now
           ) do
      ScreenPresenter.announce(context, screen, now)
      {:ok, %{screen: ScreenPresenter.view(screen, now)}}
    end
  end

  @doc "«Επιστροφή στο αυτόματο» from class `slot_id`'s remote."
  def unpin(context, slot_id, screen_id) do
    now = BoxScreens.now()

    with {:ok, class, today} <- load(context, slot_id, now),
         {:ok, screen} <- screen(context, screen_id),
         :ok <-
           BoxScreens.may_clear_class?(
             actor(context),
             class,
             screen,
             BoxScreens.active_override(screen, now),
             today
           ),
         {:ok, screen} <- BoxScreens.clear_override(context, screen.id, context.user_id, now) do
      ScreenPresenter.announce(context, screen, now)
      {:ok, %{screen: ScreenPresenter.view(screen, now)}}
    end
  end

  # A coach without a screen to choose still gets an empty list; anyone
  # else is refused.
  defp allowed?(%{manages_screens: true}, _class, _today), do: true

  defp allowed?(actor, class, today),
    do: BoxScreens.coaches_class_today?(actor, class, today)

  defp actor(context) do
    %{
      user_id: context.user_id,
      manages_screens:
        Organizations.can?(context, :manage_settings) or
          Organizations.can?(context, :manage_locations),
      scope: Organizations.location_scope(context)
    }
  end

  defp load(context, slot_id, now) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) do
      zone = Organizations.organization_timezone(context.organization_id)

      {:ok,
       %{
         id: slot.id,
         coach_user_id: slot.coach_user_id,
         location_id: slot.location_id,
         cancelled_at: slot.cancelled_at,
         date: ZonedTime.local_date(slot.scheduled_at, zone)
       }, ZonedTime.local_date(now, zone)}
    else
      _missing -> {:error, :not_found}
    end
  end

  defp screen(context, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %{} = screen <- BoxScreens.get(context, id) do
      {:ok, screen}
    else
      _missing -> {:error, :box_screen_not_found}
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
