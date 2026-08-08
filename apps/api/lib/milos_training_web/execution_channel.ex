defmodule MilosTrainingWeb.ExecutionChannel do
  use Phoenix.Channel

  alias MilosTraining.Execution

  @impl true
  def join("execution:" <> execution_id, _payload, socket) do
    current_user = socket.assigns.current_user

    case authorize_execution_join(execution_id, current_user, socket) do
      :ok -> {:ok, socket}
      :error -> {:error, %{reason: "forbidden"}}
    end
  end

  defp authorize_execution_join(execution_id, %{role: :admin}, socket) do
    case Execution.get_execution(execution_id) do
      %{organization_id: organization_id} ->
        if authorized_socket_organization?(socket, organization_id), do: :ok, else: :error

      _missing ->
        :error
    end
  end

  defp authorize_execution_join(execution_id, user, _socket) do
    if is_nil(Execution.get_execution_for_user(execution_id, user.id)), do: :error, else: :ok
  end

  defp authorized_socket_organization?(socket, organization_id) do
    case socket.assigns[:tenant_context] do
      %{organization_id: ^organization_id} -> true
      _ -> false
    end
  end
end
