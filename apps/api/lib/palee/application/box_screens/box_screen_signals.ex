defmodule Palee.Application.BoxScreens.BoxScreenSignals do
  @moduledoc """
  What box screens are told in real time (ADR-253), published on
  `Palee.PubSub` (`"box_screen:signal"`) and delivered by the web layer
  (its realtime event handler) to `box_screen:<organization_id>`:

    * `hint/3` – `box_screen:refresh` `%{kind, slot_id}`: something on the
      day changed, read `/today` again. Hints never say who;
    * `override/3` – the screen's staff override changed (only that screen
      takes it);
    * `disconnect/1` – the screen was removed or moved to another device:
      its socket closes.
  """

  @topic "box_screen:signal"

  def topic, do: @topic

  @kinds ~w(booking attendance class_cancelled schedule override result screen)

  def kinds, do: @kinds

  def hint(organization_id, kind, slot_id \\ nil)

  def hint(organization_id, kind, slot_id)
      when is_binary(organization_id) and kind in @kinds do
    publish({:box_screen_hint, %{organization_id: organization_id, kind: kind, slot_id: slot_id}})
  end

  def hint(_organization_id, _kind, _slot_id), do: :ok

  def override(organization_id, screen_id, override) do
    publish(
      {:box_screen_override,
       %{organization_id: organization_id, screen_id: screen_id, override: override}}
    )
  end

  def disconnect(screen_id), do: publish({:box_screen_disconnect, %{screen_id: screen_id}})

  defp publish(message) do
    Phoenix.PubSub.broadcast(Palee.PubSub, @topic, message)
  end
end
