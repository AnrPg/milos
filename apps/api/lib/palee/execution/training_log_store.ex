defmodule Palee.Execution.TrainingLogStore do
  @moduledoc """
  Facade over the configured training-log adapter.

  Every call must run inside a session opened by `with_tenant_context/2`
  (ADR-091) or, for owner-only cross-tenant reads, `with_owner_context/2`.
  The adapter reads `app.organization_id` / `app.user_id` from the session
  and fails closed without them.
  """

  @behaviour Palee.Execution.Ports.TrainingLogStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:palee, :training_log_store)
  end

  def with_tenant_context(%{organization_id: organization_id} = context, fun)
      when is_binary(organization_id) and is_function(fun, 0),
      do: RepoContext.run(context, fun)

  def with_tenant_context(_context, _fun), do: {:error, :organization_context_required}

  @doc "Owner-only session used to read one user's entries across tenants."
  def with_owner_context(%{user_id: user_id}, fun)
      when is_binary(user_id) and is_function(fun, 0),
      do: RepoContext.run(%{user_id: user_id}, fun)

  def with_owner_context(_context, _fun), do: {:error, :missing_ownership_scope}

  @impl true
  def create_entry(params, job_changeset), do: adapter().create_entry(params, job_changeset)

  @impl true
  def get_entry_by_idempotency_key(user_id, key),
    do: adapter().get_entry_by_idempotency_key(user_id, key)

  @impl true
  def update_entry(id, params, expected_version),
    do: adapter().update_entry(id, params, expected_version)

  @impl true
  def void_entry(id, params, expected_version),
    do: adapter().void_entry(id, params, expected_version)

  @impl true
  def get_entry(id), do: adapter().get_entry(id)

  @impl true
  def list_entries_for_user(user_id, opts \\ []),
    do: adapter().list_entries_for_user(user_id, opts)

  @impl true
  def list_live_source_reference_ids(user_id, source_type),
    do: adapter().list_live_source_reference_ids(user_id, source_type)

  @impl true
  def list_entry_items(user_id, bound, limit, scope),
    do: adapter().list_entry_items(user_id, bound, limit, scope)

  @impl true
  def set_entry_visibility(id, user_id, rung),
    do: adapter().set_entry_visibility(id, user_id, rung)

  @impl true
  def move_entries(user_id, from, to), do: adapter().move_entries(user_id, from, to)

  @impl true
  def list_for_workout(organization_id, workout_id, from, to),
    do: adapter().list_for_workout(organization_id, workout_id, from, to)
end
