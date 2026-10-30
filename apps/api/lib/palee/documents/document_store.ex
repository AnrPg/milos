defmodule Palee.Documents.DocumentStore do
  @moduledoc false
  @behaviour Palee.Documents.Ports.DocumentStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :documents_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def get_settings(context), do: tenant_call(context, :get_settings, [])
  @impl true
  def save_settings(context, attrs), do: tenant_call(context, :save_settings, [attrs])

  @impl true
  def insert_template(context, attrs), do: tenant_call(context, :insert_template, [attrs])
  @impl true
  def update_template(context, id, attrs), do: tenant_call(context, :update_template, [id, attrs])
  @impl true
  def get_template(context, id, opts), do: tenant_call(context, :get_template, [id, opts])
  @impl true
  def list_templates(context, filters), do: tenant_call(context, :list_templates, [filters])
  @impl true
  def insert_version(context, attrs), do: tenant_call(context, :insert_version, [attrs])
  @impl true
  def get_version(context, id), do: tenant_call(context, :get_version, [id])
  @impl true
  def list_versions(context, template_id), do: tenant_call(context, :list_versions, [template_id])

  @impl true
  def insert_requests(context, rows), do: tenant_call(context, :insert_requests, [rows])
  @impl true
  def get_request(context, id), do: tenant_call(context, :get_request, [id])
  @impl true
  def update_request(context, id, attrs), do: tenant_call(context, :update_request, [id, attrs])
  @impl true
  def list_requests(context, filters), do: tenant_call(context, :list_requests, [filters])
  @impl true
  def pending_request_template_ids(context, user_id),
    do: tenant_call(context, :pending_request_template_ids, [user_id])

  @impl true
  def close_requests(context, template_id, user_id, attrs),
    do: tenant_call(context, :close_requests, [template_id, user_id, attrs])

  @impl true
  def cancel_requests_for_template(context, template_id, now),
    do: tenant_call(context, :cancel_requests_for_template, [template_id, now])

  @impl true
  def insert_signature(context, attrs), do: tenant_call(context, :insert_signature, [attrs])
  @impl true
  def get_signature(context, id), do: tenant_call(context, :get_signature, [id])
  @impl true
  def list_signatures(context, filters), do: tenant_call(context, :list_signatures, [filters])
  @impl true
  def latest_signatures(context, user_ids, template_ids),
    do: tenant_call(context, :latest_signatures, [user_ids, template_ids])

  @impl true
  def insert_audit_event(context, attrs), do: tenant_call(context, :insert_audit_event, [attrs])
  @impl true
  def list_audit_events(context, filters),
    do: tenant_call(context, :list_audit_events, [filters])

  @impl true
  def insert_health_certificate(context, attrs),
    do: tenant_call(context, :insert_health_certificate, [attrs])

  @impl true
  def get_health_certificate(context, id),
    do: tenant_call(context, :get_health_certificate, [id])

  @impl true
  def delete_health_certificate(context, id),
    do: tenant_call(context, :delete_health_certificate, [id])

  @impl true
  def current_health_certificates(context, user_ids),
    do: tenant_call(context, :current_health_certificates, [user_ids])

  @impl true
  def list_health_certificates(context, user_id),
    do: tenant_call(context, :list_health_certificates, [user_id])

  @impl true
  def health_certificates_expiring(context, today, until),
    do: tenant_call(context, :health_certificates_expiring, [today, until])

  @impl true
  def mark_health_reminded(context, id, date),
    do: tenant_call(context, :mark_health_reminded, [id, date])

  @impl true
  def purge(context), do: tenant_call(context, :purge, [])
end
