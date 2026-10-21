defmodule Palee.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    setup_open_telemetry()

    children =
      [
        PaleeWeb.Telemetry,
        Palee.Repo,
        {DNSCluster, query: Application.get_env(:palee, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Palee.PubSub},
        PaleeWeb.RealtimeEventHandler,
        Palee.Infrastructure.Security.MemoryRateLimiter.TableOwner
      ]
      |> maybe_add_oban()
      |> maybe_add_redix()
      |> maybe_add_storage_reconciler()
      |> add_endpoint()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Palee.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Palee.Infrastructure.Tenancy.PrivilegeGuard.check!()
        # ADR-123: in-app notification deliveries -> analytics events.
        Palee.Application.RecordNotificationDelivered.attach()
        # ADR-152: every billed model call -> ai_usage_records.
        Palee.Application.RecordAiUsage.attach()
        {:ok, pid}

      error ->
        error
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PaleeWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_add_redix(children) do
    if Application.get_env(:palee, :start_redix, true) do
      children ++ [{Redix, {Application.fetch_env!(:palee, :redis_url), [name: :redix]}}]
    else
      children
    end
  end

  defp maybe_add_oban(children) do
    if Application.get_env(:palee, :start_oban, true) do
      List.insert_at(children, 2, {Oban, Application.fetch_env!(:palee, Oban)})
    else
      children
    end
  end

  defp add_endpoint(children), do: children ++ [PaleeWeb.Endpoint]

  defp maybe_add_storage_reconciler(children) do
    if Application.get_env(:palee, :start_storage_reconciler, true) do
      children ++ [Palee.Infrastructure.Storage.BucketReconciler]
    else
      children
    end
  end

  defp setup_open_telemetry do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit, liveview: false)
    OpentelemetryEcto.setup([:palee, :repo], db_statement: :disabled)
  end
end
