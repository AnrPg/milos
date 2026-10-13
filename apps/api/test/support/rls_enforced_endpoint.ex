defmodule MilosTrainingWeb.RLSEnforcedEndpoint do
  @moduledoc """
  TD-046: a test-only stand-in for `MilosTrainingWeb.Endpoint` that dispatches
  each request as the non-superuser runtime role, so Row Level Security applies
  to the controller/application/store code under test exactly as in production.
  Fixtures and assertions outside the request keep the superuser test role.

  It is the `@endpoint` of every `MilosTrainingWeb.ConnCase` test. A test that
  must observe behavior RLS deliberately hides can opt out with
  `@tag rls_enforced: false`, naming the debt item that explains why.
  """

  alias MilosTraining.DataCase
  alias MilosTrainingWeb.Endpoint

  def init(opts), do: Endpoint.init(opts)

  @enforced_key {__MODULE__, :enforced}

  def put_enforced(enforced?) when is_boolean(enforced?),
    do: Process.put(@enforced_key, enforced?)

  def call(conn, opts) do
    if Process.get(@enforced_key, true),
      do:
        DataCase.with_runtime_role(fn ->
          DataCase.with_clean_session(fn ->
            MilosTraining.UnscopedQueryDetector.watch(fn -> Endpoint.call(conn, opts) end)
          end)
        end),
      else: Endpoint.call(conn, opts)
  end

  defdelegate config(key), to: Endpoint
  defdelegate config(key, default), to: Endpoint
  defdelegate url(), to: Endpoint
  defdelegate path(path), to: Endpoint
  defdelegate static_path(path), to: Endpoint
  defdelegate script_name(), to: Endpoint
  defdelegate host(), to: Endpoint

  # Channel tests talk to the endpoint's PubSub directly; sockets are not
  # dispatched through call/2, so they keep the superuser role.
  defdelegate subscribe(topic), to: Endpoint
  defdelegate subscribe(topic, opts), to: Endpoint
  defdelegate unsubscribe(topic), to: Endpoint
  defdelegate broadcast(topic, event, msg), to: Endpoint
  defdelegate broadcast!(topic, event, msg), to: Endpoint
  defdelegate broadcast_from(from, topic, event, msg), to: Endpoint
  defdelegate broadcast_from!(from, topic, event, msg), to: Endpoint
  defdelegate local_broadcast(topic, event, msg), to: Endpoint
  defdelegate local_broadcast_from(from, topic, event, msg), to: Endpoint
end
