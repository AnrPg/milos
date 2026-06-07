defmodule MilosTraining.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        MilosTrainingWeb.Telemetry,
        MilosTraining.Repo,
        {DNSCluster, query: Application.get_env(:milos_training, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: MilosTraining.PubSub}
      ]
      |> maybe_add_oban()
      |> maybe_add_redix()
      |> add_endpoint()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MilosTraining.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MilosTrainingWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_redix(children) do
    if Application.get_env(:milos_training, :start_redix, true) do
      children ++ [{Redix, {Application.fetch_env!(:milos_training, :redis_url), [name: :redix]}}]
    else
      children
    end
  end

  defp maybe_add_oban(children) do
    if Application.get_env(:milos_training, :start_oban, true) do
      List.insert_at(children, 2, {Oban, Application.fetch_env!(:milos_training, Oban)})
    else
      children
    end
  end

  defp add_endpoint(children), do: children ++ [MilosTrainingWeb.Endpoint]
end
