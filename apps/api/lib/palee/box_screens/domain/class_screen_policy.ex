defmodule Palee.BoxScreens.Domain.ClassScreenPolicy do
  @moduledoc """
  Who may change what a box screen shows for one class, from the class
  timer's remote (ADR-253, update 2026-10-29). Pure.

    * **Screen managers** (staff with `manage_settings` or
      `manage_locations`) may, as on Staff › Box screens: any screen of
      their branches (a whole-box screen needs staff of every branch), any
      override view.
    * **The class's coach** may, only for their own class: a class they
      coach (`coach_user_id`), held today on the box's clock and not
      cancelled, on a screen of the class's branch or a whole-box screen
      (a whole-box class shows on every screen). They pin its `timer`,
      `leaderboard` or `wod` (always with the class's `slot_id`) and return
      the screen to automatic only while what is pinned is their class, or
      nothing is.
    * Anyone else, a coach of another class included, is refused.

  `actor` is `%{user_id, manages_screens, scope}` (`scope`: `:all` or the
  branch ids of a branch-scoped staff member, ADR-186); `class` is
  `%{id, coach_user_id, location_id, cancelled_at, date}` where `date` is
  its day on the box's clock.
  """

  alias Palee.BoxScreens.Domain.ScreenPolicy

  @coach_views ~w(timer leaderboard wod)

  @doc "The views a coach may pin for their class."
  def coach_views, do: @coach_views

  @doc "The views `actor` may pin for `class`."
  def views(%{manages_screens: true}), do: ScreenPolicy.override_views()
  def views(_actor), do: @coach_views

  @doc "`true` when `screen` shows `class`: the class's branch, a whole-box screen or class."
  def shows?(%{location_id: nil}, _class), do: true

  def shows?(%{location_id: location_id}, %{location_id: class_location}),
    do: class_location in [nil, location_id]

  @doc "`true` when `actor` coaches `class` today (the class is not cancelled)."
  def coaches_today?(%{user_id: user_id}, class, %Date{} = today) do
    is_binary(user_id) and class.coach_user_id == user_id and is_nil(class.cancelled_at) and
      Date.compare(class.date, today) == :eq
  end

  @doc "The screens that show `class` and that `actor` may change, out of `screens`."
  def screens(actor, class, screens, %Date{} = today),
    do: Enum.filter(screens, &(shows?(&1, class) and may_change?(actor, class, &1, today) == :ok))

  @doc """
  `:ok` when `actor` may pin `class` on `screen` with `view`, else
  `{:error, :forbidden}` (or `{:error, :invalid_screen_override}` for a
  view the actor may not pin).
  """
  def may_pin?(actor, class, screen, view, %Date{} = today) do
    with :ok <- may_change?(actor, class, screen, today) do
      if view in views(actor), do: :ok, else: {:error, :invalid_screen_override}
    end
  end

  @doc """
  `:ok` when `actor` may return `screen` to automatic from `class`'s
  remote: a screen manager always; the class's coach while the active
  `override` is nil or is their class.
  """
  def may_clear?(%{manages_screens: true} = actor, class, screen, _override, today),
    do: may_change?(actor, class, screen, today)

  def may_clear?(actor, class, screen, override, %Date{} = today) do
    with :ok <- may_change?(actor, class, screen, today) do
      case override do
        nil -> :ok
        %{slot_id: slot_id} when slot_id == class.id -> :ok
        _other_choice -> {:error, :forbidden}
      end
    end
  end

  defp may_change?(%{manages_screens: true, scope: scope}, _class, screen, _today) do
    if ScreenPolicy.in_scope?(scope, screen.location_id), do: :ok, else: {:error, :forbidden}
  end

  defp may_change?(actor, class, screen, today) do
    if coaches_today?(actor, class, today) and shows?(screen, class),
      do: :ok,
      else: {:error, :forbidden}
  end
end
