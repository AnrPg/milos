defmodule Palee.Application.BoxScreens.ScreenPresenter do
  @moduledoc """
  A box screen as staff and coaches see it (ADR-253), and telling the
  paired TV that its override changed. Shared by `BoxScreenAdmin` (Staff ›
  Box screens) and `ClassScreens` (a class timer's «Στην οθόνη»).
  """

  alias Palee.{BoxScreens, Identity}
  alias Palee.Application.BoxScreens.BoxScreenSignals

  @doc "The screen's public view; `names` maps user ids to display names."
  def view(screen, names, now) do
    %{
      id: screen.id,
      name: screen.name,
      location_id: screen.location_id,
      paired: not is_nil(screen.paired_at),
      paired_at: screen.paired_at,
      last_seen_at: screen.last_seen_at,
      pairing_expires_at: pending_code(screen, now),
      override: BoxScreens.active_override(screen, now),
      focus_changed:
        screen.focus_changed_at &&
          %{
            at: screen.focus_changed_at,
            by:
              screen.focus_changed_by_id &&
                %{
                  id: screen.focus_changed_by_id,
                  name: Map.get(names, screen.focus_changed_by_id)
                }
          },
      inserted_at: screen.inserted_at
    }
  end

  @doc "The view of one screen, with the name of who changed it last."
  def view(screen, now), do: view(screen, names([screen.focus_changed_by_id]), now)

  @doc "`%{user_id => nickname}` for `ids`."
  def names(ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
    end
  end

  @doc "The paired TV hears its new override at once; the box's screens refresh."
  def announce(context, screen, now) do
    override = BoxScreens.active_override(screen, now)
    BoxScreenSignals.override(context.organization_id, screen.id, override)
    BoxScreenSignals.hint(context.organization_id, "override", override && override.slot_id)
  end

  defp pending_code(%{pairing_code_expires_at: %DateTime{} = at}, now),
    do: if(DateTime.compare(at, now) == :gt, do: at)

  defp pending_code(_screen, _now), do: nil
end
