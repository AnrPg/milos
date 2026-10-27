defmodule Palee.Identity.AccountDeletionStore do
  @moduledoc "Facade over the account deletion storage adapter (ADR-211)."
  @behaviour Palee.Identity.Ports.AccountDeletionStore

  @impl true
  def for_login(login_id), do: impl().for_login(login_id)
  @impl true
  def get(id), do: impl().get(id)
  @impl true
  def open(attrs), do: impl().open(attrs)
  @impl true
  def schedule(id, now, scheduled_for), do: impl().schedule(id, now, scheduled_for)
  @impl true
  def delete(id), do: impl().delete(id)
  @impl true
  def due(now, limit), do: impl().due(now, limit)
  @impl true
  def sole_owned_organizations(user_ids), do: impl().sole_owned_organizations(user_ids)
  @impl true
  def has_retained_records?(user_id), do: impl().has_retained_records?(user_id)
  @impl true
  def anonymize_profile(user_id), do: impl().anonymize_profile(user_id)
  @impl true
  def delete_login_if_empty(login_id), do: impl().delete_login_if_empty(login_id)

  defp impl do
    Application.get_env(
      :palee,
      :account_deletion_store,
      Palee.Infrastructure.Identity.EctoAccountDeletionStore
    )
  end
end
