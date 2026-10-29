defmodule Palee.Application.BoxScreens.BoxScreenDisplay do
  @moduledoc """
  The TV's side of a box screen (ADR-253), behind `/api/box-screen/*` and
  `/box_screen_socket`:

    * `pair/1` – the code typed on the TV: found outside any tenant (the
      narrow `palee_box_screen_pairing` lookup), then claimed in the box's
      scope with the row locked, so a code pairs one device once. The
      previous device of that screen is disconnected;
    * `authenticate/1` – a display token back to its screen, while the
      screen exists and the token's version is the screen's;
    * `renew/1`, `today/1`, `class_timer/2`.

  Every moment comes from the injected clock (`BoxScreens.clock/0`).
  """

  alias Palee.{BoxScreens, Organizations, Scheduling}
  alias Palee.Application.BoxScreens.{BoxScreenSignals, BoxScreenToday, DisplayToken}
  alias Palee.Application.ClassTimerView

  @doc "`{:ok, %{token, expires_at, screen, box}}` or `{:error, :invalid_pairing_code}`."
  def pair(params) do
    now = BoxScreens.now()

    with {:ok, organization_id, screen_id, hash} <-
           BoxScreens.find_pairing(param(params, :code), now),
         {:ok, context} <- context(organization_id),
         {:ok, screen} <- BoxScreens.claim(context, screen_id, hash, now) do
      BoxScreenSignals.disconnect(screen.id)

      {:ok,
       screen
       |> DisplayToken.issue(now)
       |> Map.merge(%{
         screen: %{id: screen.id, name: screen.name},
         box: %{name: context.organization.name}
       })}
    else
      _invalid -> {:error, :invalid_pairing_code}
    end
  end

  @doc """
  `{:ok, %{context, screen}}` for a valid display token, else
  `{:error, :invalid_screen_token}`.
  """
  def authenticate(token) do
    with {:ok, claims} <- DisplayToken.verify(token),
         {:ok, context} <- context(claims.organization_id),
         %{token_version: version} = screen <- BoxScreens.get(context, claims.screen_id),
         true <- version == claims.token_version do
      {:ok, %{context: context, screen: screen}}
    else
      _invalid -> {:error, :invalid_screen_token}
    end
  end

  @doc "A fresh token for the same screen and version (`%{token, expires_at}`)."
  def renew(%{screen: screen}), do: {:ok, DisplayToken.issue(screen, BoxScreens.now())}

  @doc "The day the screen shows (`BoxScreenToday`)."
  def today(%{context: context, screen: screen}) do
    now = BoxScreens.now()
    BoxScreens.touch(context, screen.id, now)
    {:ok, BoxScreenToday.build(context, screen, now)}
  end

  @doc "A class's timer (the wall-display payload), for a class the screen shows."
  def class_timer(%{context: context, screen: screen}, slot_id) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id),
         true <- BoxScreenToday.shows?(screen, slot),
         {:ok, view} <- ClassTimerView.load(context, slot_id) do
      {:ok, ClassTimerView.payload(view, BoxScreens.now())}
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc "Whether the screen may follow `slot_id`'s class timer (socket)."
  def follows_class?(%{context: context, screen: screen}, slot_id) do
    with {:ok, slot_id} <- Ecto.UUID.cast(slot_id),
         %{} = slot <- Scheduling.get_slot(context, slot_id) do
      BoxScreenToday.shows?(screen, slot)
    else
      _missing -> false
    end
  end

  defp context(organization_id),
    do: Organizations.resolve_system_tenant_context(organization_id, :box_screen)

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
