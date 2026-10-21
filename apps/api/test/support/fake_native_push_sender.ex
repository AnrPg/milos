defmodule MilosTraining.FakeNativePushSender do
  @moduledoc """
  Native push senders for tests (ADR-171). Off unless a test turns a
  provider on with `enable/1`; sends are recorded to the subscribed process.
  Tokens starting with `gone` answer `{:error, :expired}`, tokens starting
  with `fail` a provider error.
  """

  def enable(providers) when is_list(providers),
    do: Application.put_env(:milos_training, :fake_native_push, providers)

  def disable, do: Application.delete_env(:milos_training, :fake_native_push)

  def subscribe, do: :persistent_term.put({__MODULE__, :listener}, self())
  def unsubscribe, do: :persistent_term.erase({__MODULE__, :listener})

  def configured?(provider),
    do: provider in Application.get_env(:milos_training, :fake_native_push, [])

  def send_push(provider, token, message) do
    case :persistent_term.get({__MODULE__, :listener}, nil) do
      pid when is_pid(pid) -> send(pid, {:native_push, provider, token, message})
      nil -> :ok
    end

    cond do
      String.starts_with?(token.token, "gone") -> {:error, :expired}
      String.starts_with?(token.token, "fail") -> {:error, {:http_error, 500, %{}}}
      true -> :ok
    end
  end

  defmodule Fcm do
    @moduledoc false
    @behaviour MilosTraining.Notifications.Ports.NativePushSender

    @impl true
    def configured?, do: MilosTraining.FakeNativePushSender.configured?(:fcm)

    @impl true
    def send_push(token, message),
      do: MilosTraining.FakeNativePushSender.send_push(:fcm, token, message)
  end

  defmodule Apns do
    @moduledoc false
    @behaviour MilosTraining.Notifications.Ports.NativePushSender

    @impl true
    def configured?, do: MilosTraining.FakeNativePushSender.configured?(:apns)

    @impl true
    def send_push(token, message),
      do: MilosTraining.FakeNativePushSender.send_push(:apns, token, message)
  end
end
