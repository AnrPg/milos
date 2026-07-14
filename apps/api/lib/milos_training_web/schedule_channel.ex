defmodule MilosTrainingWeb.ScheduleChannel do
  use Phoenix.Channel

  @impl true
  def join("schedule:lobby", _payload, socket) do
    case socket.assigns[:current_user] do
      %{role: role} when role in [:member, :admin, :athlete] -> {:ok, socket}
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end
end
