defmodule MilosTraining.FakeWalletUpdater do
  @moduledoc "Records Wallet updates (ADR-155) as messages to the processes that subscribed."
  @behaviour MilosTraining.Wallet.Ports.PassUpdater

  def subscribe, do: :persistent_term.put({__MODULE__, :listener}, self())
  def unsubscribe, do: :persistent_term.erase({__MODULE__, :listener})

  @impl true
  def configured?, do: true

  @impl true
  def update(update) do
    case :persistent_term.get({__MODULE__, :listener}, nil) do
      pid when is_pid(pid) -> send(pid, {:wallet_update, update})
      nil -> :ok
    end

    gone = update |> Map.get(:push_tokens, []) |> Enum.filter(&String.starts_with?(&1, "gone"))
    {:ok, %{gone: gone}}
  end
end

defmodule MilosTraining.FakeWalletImageSource do
  @moduledoc false
  @behaviour MilosTraining.Wallet.Ports.ImageSource

  @impl true
  def fetch(_url), do: {:error, :not_fetched_in_tests}
end
