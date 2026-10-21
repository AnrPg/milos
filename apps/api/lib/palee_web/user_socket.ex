defmodule PaleeWeb.UserSocket do
  use Phoenix.Socket

  alias Palee.Infrastructure.Auth.Guardian
  alias Palee.Application.ResolveTenantContext
  alias Palee.Identity.UserContext

  channel "schedule:*", PaleeWeb.ScheduleChannel
  channel "notifications:*", PaleeWeb.NotificationChannel
  channel "sync:*", PaleeWeb.SyncChannel
  channel "execution:*", PaleeWeb.ExecutionChannel
  channel "chat:*", PaleeWeb.ChatChannel
  channel "class_timer:*", PaleeWeb.ClassTimerChannel
  channel "community:*", PaleeWeb.CommunityChannel
  channel "check_in:*", PaleeWeb.CheckInChannel
  channel "user:*", PaleeWeb.UserChannel

  @impl true
  def connect(%{"token" => token} = params, socket, _connect_info) when is_binary(token) do
    with {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      socket =
        socket
        |> assign(:current_user, user)
        |> assign(:user_context, UserContext.new(user, %{transport: :socket}))

      assign_optional_tenant(socket, user, Map.get(params, "organization_slug"))
    else
      _error -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"

  defp assign_optional_tenant(socket, _user, nil), do: {:ok, socket}

  defp assign_optional_tenant(socket, user, slug) do
    case ResolveTenantContext.call(user, slug, %{transport: :socket}) do
      {:ok, context} -> {:ok, assign(socket, :tenant_context, context)}
      {:error, _reason} -> :error
    end
  end
end
