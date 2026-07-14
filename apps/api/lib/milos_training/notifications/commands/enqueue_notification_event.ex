defmodule MilosTraining.Notifications.Commands.EnqueueNotificationEvent do
  alias MilosTraining.Notifications.Domain.PayloadNormalizer
  alias MilosTraining.Workers.NotificationEventJob

  def call(event, payload) when is_atom(event) and is_map(payload) do
    %{event: Atom.to_string(event), payload: PayloadNormalizer.normalize(payload)}
    |> NotificationEventJob.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    RuntimeError -> {:error, :oban_unavailable}
  end

  def call(_event, _payload), do: {:error, :bad_request}
end
