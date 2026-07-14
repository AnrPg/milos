defmodule MilosTrainingWeb.ExecutionChannel do
  use Phoenix.Channel

  alias MilosTraining.Execution

  @impl true
  def join("execution:" <> execution_id, _payload, socket) do
    current_user = socket.assigns.current_user

    case authorize_execution_join(execution_id, current_user) do
      :ok -> {:ok, socket}
      :error -> {:error, %{reason: "forbidden"}}
    end
  end

  defp authorize_execution_join(execution_id, %{role: :admin}) do
    if is_nil(Execution.get_execution(execution_id)), do: :error, else: :ok
  end

  defp authorize_execution_join(execution_id, user) do
    if is_nil(Execution.get_execution_for_user(execution_id, user.id)), do: :error, else: :ok
  end
end
