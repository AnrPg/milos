defmodule Palee.Documents.Ports.DocumentStore do
  @moduledoc """
  Persistence of the Documents context (ADR-252). Every callback takes the
  tenant context first; the facade (`Palee.Documents.DocumentStore`) opens
  the tenant session.

  Versions, signatures and audit events are insert-only. Publishing a
  version and signing lock the template row (`get_template(.., lock:
  true)`) inside `transaction/2`, so numbers never collide and a signature
  always names the version that was current when it was written.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()
  @type result(value) :: {:ok, value} | {:error, term()}

  @doc "Runs `fun` in one tenant transaction; `{:error, reason}` from it rolls everything back."
  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) :: result(term())

  # Settings
  @callback get_settings(context()) :: map() | nil
  @callback save_settings(context(), map()) :: result(map())

  # Templates and versions
  @callback insert_template(context(), map()) :: result(map())
  @callback update_template(context(), id(), map()) :: result(map())
  @callback get_template(context(), id(), keyword()) :: map() | nil
  @doc "Templates, active first then by title; filters: `status`, `requirement`."
  @callback list_templates(context(), map()) :: [map()]
  @callback insert_version(context(), map()) :: result(map())
  @callback get_version(context(), id()) :: map() | nil
  @doc "A template's versions, newest first, without their bodies."
  @callback list_versions(context(), id()) :: [map()]

  # Requests
  @doc "Inserts pending requests, skipping people who already have one; returns the inserted rows."
  @callback insert_requests(context(), [map()]) :: result([map()])
  @callback get_request(context(), id()) :: map() | nil
  @callback update_request(context(), id(), map()) :: result(map())
  @doc "Requests, newest first; filters: status, template_id, user_id, batch_id, limit, offset."
  @callback list_requests(context(), map()) :: %{requests: [map()], total: non_neg_integer()}
  @doc "Template ids with a pending request for `user_id`."
  @callback pending_request_template_ids(context(), id()) :: [id()]
  @doc "Marks `user_id`'s pending requests for the template signed; returns their ids."
  @callback close_requests(context(), id(), id(), map()) :: [id()]
  @doc "Cancels every pending request for a template (archiving it)."
  @callback cancel_requests_for_template(context(), id(), DateTime.t()) :: non_neg_integer()

  # Signatures
  @callback insert_signature(context(), map()) :: result(map())
  @callback get_signature(context(), id()) :: map() | nil
  @doc "Signatures, newest first; filters: template_id, user_id, limit, offset."
  @callback list_signatures(context(), map()) :: %{signatures: [map()], total: non_neg_integer()}
  @doc "Each person's latest signature per template: `%{{user_id, template_id} => signature}`."
  @callback latest_signatures(context(), [id()] | :all, [id()]) :: %{{id(), id()} => map()}

  # Audit
  @callback insert_audit_event(context(), map()) :: result(map())
  @doc "Audit events, newest first; filters: subject_id, action, limit, offset."
  @callback list_audit_events(context(), map()) :: %{events: [map()], total: non_neg_integer()}

  # Health certificates
  @callback insert_health_certificate(context(), map()) :: result(map())
  @callback get_health_certificate(context(), id()) :: map() | nil
  @callback delete_health_certificate(context(), id()) :: result(map())
  @doc "Each person's certificate with the latest expiry: `%{user_id => certificate}`."
  @callback current_health_certificates(context(), [id()] | :all) :: %{id() => map()}
  @doc "A person's certificates, latest expiry first."
  @callback list_health_certificates(context(), id()) :: [map()]
  @doc "Certificates expiring on or before `until` and after `today` that were not reminded."
  @callback health_certificates_expiring(context(), Date.t(), Date.t()) :: [map()]
  @callback mark_health_reminded(context(), id(), Date.t()) :: :ok

  @doc "Deletes all documents rows of the tenant (purge after retention only)."
  @callback purge(context()) :: result(%{String.t() => non_neg_integer()})
end
