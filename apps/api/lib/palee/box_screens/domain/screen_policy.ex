defmodule Palee.BoxScreens.Domain.ScreenPolicy do
  @moduledoc """
  Rules for box screens (ADR-253), pure:

    * a name of 1–60 characters (trimmed);
    * at most #{20} screens per box;
    * a staff override names what the screen shows (`wod`, `timer`,
      `leaderboard`, `bookings` or one `class`), optionally one of today's
      classes, and optionally a time it ends (in the future, at most 24 hours
      away). Without an end it stays until staff return the screen to
      automatic.
  """

  @max_screens 20
  @name_max 60
  @override_views ~w(wod timer leaderboard bookings class)
  @override_max_hours 24

  def max_screens, do: @max_screens
  def override_views, do: @override_views

  @doc "`{:ok, name}` or `{:error, :invalid_screen_name}`."
  def name(value) when is_binary(value) do
    name = value |> String.trim() |> String.replace(~r/\s+/u, " ")

    if name != "" and String.length(name) <= @name_max,
      do: {:ok, name},
      else: {:error, :invalid_screen_name}
  end

  def name(_value), do: {:error, :invalid_screen_name}

  @doc "`:ok` while the box has room for one more screen."
  def can_add?(count) when count < @max_screens, do: :ok
  def can_add?(_count), do: {:error, :too_many_screens}

  @doc """
  Validates an override request against today's classes of the screen
  (`slot_ids`). `{:ok, %{override_view, override_slot_id, override_until}}`
  or `{:error, :invalid_screen_override}`.
  """
  def override(params, slot_ids, %DateTime{} = now) do
    view = params[:view]
    slot_id = blank(params[:slot_id])

    with true <- view in @override_views,
         true <- view != "class" or is_binary(slot_id),
         true <- is_nil(slot_id) or slot_id in slot_ids,
         {:ok, until} <- until(params[:until], now) do
      {:ok, %{override_view: view, override_slot_id: slot_id, override_until: until}}
    else
      _invalid -> {:error, :invalid_screen_override}
    end
  end

  defp until(nil, _now), do: {:ok, nil}
  defp until("", _now), do: {:ok, nil}

  defp until(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> until(at, now)
      _invalid -> :error
    end
  end

  defp until(%DateTime{} = at, now) do
    if DateTime.compare(at, now) == :gt and
         DateTime.diff(at, now, :second) <= @override_max_hours * 3600,
       do: {:ok, at |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)},
       else: :error
  end

  defp until(_value, _now), do: :error

  @doc "The override still in force at `now`, or nil."
  def active_override(%{override_view: nil}, _now), do: nil

  def active_override(%{override_view: view} = screen, now) when is_binary(view) do
    case screen.override_until do
      nil ->
        %{view: view, slot_id: screen.override_slot_id, until: nil}

      until ->
        if DateTime.compare(until, now) == :gt,
          do: %{view: view, slot_id: screen.override_slot_id, until: until},
          else: nil
    end
  end

  def active_override(_screen, _now), do: nil

  @doc """
  Whether staff working at `scope` (`:all` or branch ids) may manage a
  screen of `location_id` (nil: the whole box, only for staff of every
  branch).
  """
  def in_scope?(:all, _location_id), do: true
  def in_scope?(scope, location_id) when is_list(scope), do: location_id in scope

  defp blank(""), do: nil
  defp blank(value), do: value
end
