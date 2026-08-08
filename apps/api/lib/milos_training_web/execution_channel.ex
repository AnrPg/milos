defmodule MilosTrainingWeb.ExecutionChannel do
  use Phoenix.Channel

  alias MilosTraining.Execution
  alias MilosTraining.Execution.ExecutionStore
  alias MilosTraining.Organizations

  @impl true
  def join("execution:" <> execution_id, _payload, socket) do
    current_user = socket.assigns.current_user

    case authorize_execution_join(execution_id, current_user, socket) do
      :ok -> {:ok, socket}
      :error -> {:error, %{reason: "forbidden"}}
    end
  end

  defp authorize_execution_join(execution_id, current_user, socket) do
    context = socket.assigns[:tenant_context] || socket.assigns[:user_context]

    ExecutionStore.with_authorization_context(context, fn ->
      case Execution.get_execution(execution_id) do
        %{user_id: user_id} when user_id == current_user.id ->
          :ok

        %{organization_id: organization_id} ->
          if authorized_staff_member?(current_user, organization_id, socket),
            do: :ok,
            else: :error

        _missing ->
          :error
      end
    end)
  end

  defp authorized_staff_member?(user, organization_id, socket) do
    if authorized_socket_organization?(socket, organization_id) do
      user.id
      |> Organizations.list_memberships()
      |> Enum.any?(fn %{membership: membership, organization: organization} ->
        organization.id == organization_id and membership.status == :active and
          membership.role in [:owner, :admin, :coach]
      end)
    else
      false
    end
  end

  defp authorized_socket_organization?(socket, organization_id) do
    case socket.assigns[:tenant_context] do
      %{organization_id: socket_organization_id} ->
        socket_organization_id == organization_id

      _ ->
        false
    end
  end
end
