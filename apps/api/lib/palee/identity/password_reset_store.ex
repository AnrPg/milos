defmodule Palee.Identity.PasswordResetStore do
  @moduledoc "Facade over the password reset storage adapter (ADR-187)."
  @behaviour Palee.Identity.Ports.PasswordResetStore

  @impl true
  def handlers(login_id), do: impl().handlers(login_id)
  @impl true
  def get_request(id), do: impl().get_request(id)
  @impl true
  def get_request_for_login(login_id), do: impl().get_request_for_login(login_id)
  @impl true
  def get_request_by_token_hash(hash), do: impl().get_request_by_token_hash(hash)
  @impl true
  def lock_request_by_token_hash(hash), do: impl().lock_request_by_token_hash(hash)
  @impl true
  def count_requests_from(requester_key, since),
    do: impl().count_requests_from(requester_key, since)

  @impl true
  def transaction(fun), do: impl().transaction(fun)
  @impl true
  def create_request(params), do: impl().create_request(params)
  @impl true
  def update_request_locked(id, fun), do: impl().update_request_locked(id, fun)
  @impl true
  def delete_request(id), do: impl().delete_request(id)
  @impl true
  def inbox(viewer_id), do: impl().inbox(viewer_id)
  @impl true
  def inbox_entry(viewer_id, request_id), do: impl().inbox_entry(viewer_id, request_id)
  @impl true
  def hide(request_id, viewer_id), do: impl().hide(request_id, viewer_id)
  @impl true
  def log(params), do: impl().log(params)
  @impl true
  def list_log(limit), do: impl().list_log(limit)
  @impl true
  def replace_recovery_codes(login_id, hashes),
    do: impl().replace_recovery_codes(login_id, hashes)

  @impl true
  def count_recovery_codes(login_id), do: impl().count_recovery_codes(login_id)
  @impl true
  def use_recovery_code(login_id, hash, now), do: impl().use_recovery_code(login_id, hash, now)

  defp impl, do: Application.fetch_env!(:palee, :password_reset_store)
end
