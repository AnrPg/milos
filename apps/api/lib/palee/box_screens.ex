defmodule Palee.BoxScreens do
  @moduledoc """
  The BoxScreens bounded context (ADR-253): TVs on a box's wall
  («Οθόνη box»).

    * staff create a screen (a name and, optionally, a branch) and get a
      pairing code («Κωδικός σύνδεσης») to type on the TV; a new code moves
      the screen to another device;
    * the TV pairs with the code once and then shows the day with a display
      token that names the box, the screen and the screen's token version;
    * staff may pin what a screen shows (an override) and return it to
      automatic; a class's coach may do so for their own class today
      (`ClassScreenPolicy`).

  BoxScreens owns only its table; what a screen shows (classes, WODs,
  leaderboards, timers) is gathered by `Palee.Application.BoxScreens.*`.
  """

  alias Palee.BoxScreens.BoxScreenStore
  alias Palee.BoxScreens.Domain.{
    ClassScreenPolicy,
    Focus,
    PairingCode,
    ScreenPolicy,
    TenantDataPolicy
  }

  @doc "The configured clock (`BoxScreens.Ports.Clock`)."
  def clock, do: Application.fetch_env!(:palee, :box_screen_clock)

  def now, do: clock().now()

  # ── Screens ─────────────────────────────────────────────────────────────

  def list(context), do: BoxScreenStore.list(context)

  def get(context, id), do: BoxScreenStore.get(context, id)

  @doc """
  Creates a screen with a fresh pairing code.
  `{:ok, screen, %{code, expires_at}}` or an error.
  """
  def create(context, %{name: name} = attrs, actor_id, %DateTime{} = now) do
    {code, code_attrs} = new_code(now)

    with {:ok, name} <- ScreenPolicy.name(name),
         :ok <- ScreenPolicy.can_add?(BoxScreenStore.count(context)),
         {:ok, screen} <-
           BoxScreenStore.insert(
             context,
             Map.merge(code_attrs, %{
               name: name,
               location_id: attrs[:location_id],
               created_by_id: actor_id
             })
           ) do
      {:ok, screen, %{code: code, expires_at: screen.pairing_code_expires_at}}
    end
  end

  @doc "Renames a screen or moves it to another branch."
  def update(context, id, changes) do
    with {:ok, changes} <- name_change(changes),
         {:ok, screen} <- BoxScreenStore.update(context, id, changes) do
      {:ok, screen}
    end
  end

  defp name_change(%{name: name} = changes) do
    with {:ok, name} <- ScreenPolicy.name(name), do: {:ok, %{changes | name: name}}
  end

  defp name_change(changes), do: {:ok, changes}

  @doc "Removes a screen; its display token stops working at once."
  def delete(context, id), do: BoxScreenStore.delete(context, id)

  @doc """
  A new pairing code for a screen, replacing any pending one. The screen's
  current TV keeps working until another device pairs with the code.
  """
  def new_pairing_code(context, id, %DateTime{} = now) do
    {code, attrs} = new_code(now)

    with {:ok, screen} <- BoxScreenStore.update(context, id, attrs) do
      {:ok, screen, %{code: code, expires_at: screen.pairing_code_expires_at}}
    end
  end

  defp new_code(now) do
    code = PairingCode.generate()
    {:ok, hash} = PairingCode.hash(code)

    {code,
     %{
       pairing_code_hash: hash,
       pairing_code_expires_at: now |> PairingCode.expires_at() |> DateTime.truncate(:second)
     }}
  end

  # ── Pairing ─────────────────────────────────────────────────────────────

  @doc """
  The box and screen an unexpired code names: `{:ok, organization_id,
  screen_id, hash}` or `{:error, :invalid_pairing_code}`. Runs outside any
  tenant.
  """
  def find_pairing(typed, %DateTime{} = now) do
    with {:ok, hash} <- PairingCode.hash(typed),
         {organization_id, screen_id} <- BoxScreenStore.find_pairing(hash, now) do
      {:ok, organization_id, screen_id, hash}
    else
      _invalid -> {:error, :invalid_pairing_code}
    end
  end

  @doc "Spends the code in the box's scope (row locked): `{:ok, screen}` once."
  def claim(context, screen_id, hash, %DateTime{} = now),
    do: BoxScreenStore.claim(context, screen_id, hash, now)

  def touch(context, id, %DateTime{} = now), do: BoxScreenStore.touch(context, id, now)

  # ── Override ────────────────────────────────────────────────────────────

  @doc """
  Pins what a screen shows. `slot_ids` are today's classes of the screen.
  Records who changed it and when.
  """
  def set_override(context, id, params, slot_ids, actor_id, %DateTime{} = now) do
    with {:ok, attrs} <- ScreenPolicy.override(params, slot_ids, now) do
      BoxScreenStore.update(
        context,
        id,
        Map.merge(attrs, %{focus_changed_by_id: actor_id, focus_changed_at: now})
      )
    end
  end

  @doc "«Επιστροφή στο αυτόματο»: the screen follows the day again."
  def clear_override(context, id, actor_id, %DateTime{} = now) do
    BoxScreenStore.update(context, id, %{
      override_view: nil,
      override_slot_id: nil,
      override_until: nil,
      focus_changed_by_id: actor_id,
      focus_changed_at: now
    })
  end

  defdelegate active_override(screen, now), to: ScreenPolicy
  defdelegate focus(classes, override, now), to: Focus, as: :resolve
  defdelegate ends_at(class), to: Focus
  defdelegate max_screens(), to: ScreenPolicy
  defdelegate in_scope?(scope, location_id), to: ScreenPolicy
  defdelegate override_views(), to: ScreenPolicy

  # ── One class, from its timer remote (ADR-253 update 2026-10-29) ───────

  defdelegate class_screens(actor, class, screens, today), to: ClassScreenPolicy, as: :screens
  defdelegate class_views(actor), to: ClassScreenPolicy, as: :views
  defdelegate may_pin_class?(actor, class, screen, view, today), to: ClassScreenPolicy, as: :may_pin?

  defdelegate may_clear_class?(actor, class, screen, override, today),
    to: ClassScreenPolicy,
    as: :may_clear?

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
