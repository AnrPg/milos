defmodule Palee.Documents do
  @moduledoc """
  The Documents bounded context (ADR-252, V3-M8): what a box asks its
  clients to read and sign, and their health certificates.

    * documents (waiver, terms, privacy, health declaration, other) with
      immutable versions and a staff-set requirement (`mandatory` blocks
      booking and counts as outstanding; `optional` is only offered);
    * signature requests, to one person or in bulk;
    * simple electronic signatures with their evidence and a PDF
      certificate (ports `SignatureEvidenceStore`, `CertificateRenderer`);
    * health certificates: dates and file only;
    * the booking gate and the box's settings;
    * an insert-only audit log of every change and every look at a health
      certificate.

  Documents never reads other contexts' tables: callers hand it people
  (the signer's account, the recipients of a bulk send) and the gym's date.
  """

  alias Palee.Documents.Domain.{
    HealthCertificatePolicy,
    MemberDocuments,
    SettingsPolicy,
    SignaturePolicy,
    StarterTemplates,
    TemplatePolicy,
    TenantDataPolicy
  }

  alias Palee.Documents.DocumentStore

  # ── Ports ───────────────────────────────────────────────────────────────

  @doc "The configured evidence store (`Documents.Ports.SignatureEvidenceStore`)."
  def evidence_store, do: Application.fetch_env!(:palee, :documents_evidence_store)

  @doc "The configured certificate renderer (`Documents.Ports.CertificateRenderer`)."
  def certificate_renderer, do: Application.fetch_env!(:palee, :documents_certificate_renderer)

  defdelegate kinds(), to: TemplatePolicy
  defdelegate requirements(), to: TemplatePolicy
  defdelegate languages(), to: TemplatePolicy
  defdelegate change_kinds(), to: TemplatePolicy
  defdelegate health_content_types(), to: HealthCertificatePolicy, as: :content_types
  defdelegate health_max_bytes(), to: HealthCertificatePolicy, as: :max_bytes

  defdelegate validate_health_upload(content_type),
    to: HealthCertificatePolicy,
    as: :validate_upload

  defdelegate validate_health_file(content_type, head, byte_size),
    to: HealthCertificatePolicy,
    as: :validate_file

  defdelegate health_relative_key(user_id, extension),
    to: HealthCertificatePolicy,
    as: :relative_key

  defdelegate health_key_of?(key, prefix, user_id), to: HealthCertificatePolicy, as: :key_of?

  @doc "Draft documents a box can start from (always marked for legal review)."
  def starter_templates(language \\ nil), do: StarterTemplates.list(language)

  # ── Settings ────────────────────────────────────────────────────────────

  @doc "The box's effective settings (defaults when never saved)."
  def settings(context), do: context |> DocumentStore.get_settings() |> SettingsPolicy.effective()

  @doc "Saves settings and audits the fields that changed."
  def save_settings(context, changes, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      before = settings(context)

      with {:ok, merged} <- SettingsPolicy.validate(before, changes),
           {:ok, _saved} <-
             DocumentStore.save_settings(context, Map.put(merged, :updated_by_id, actor_id)) do
        case SettingsPolicy.changed(before, merged) do
          [] ->
            {:ok, merged}

          changed ->
            with {:ok, _event} <-
                   audit(context, "settings_changed", "document_settings", nil, actor_id, now, %{
                     changed: changed,
                     before: Map.take(before, changed),
                     after: Map.take(merged, changed)
                   }) do
              {:ok, merged}
            end
        end
      end
    end)
  end

  # ── Templates and versions ──────────────────────────────────────────────

  @doc """
  Creates a document with its first version (always `major`) and audits
  the publish. `attrs`: kind, title, requirement, body, language.
  """
  def create_template(context, attrs, actor_id, %DateTime{} = now) do
    with {:ok, template_attrs} <- TemplatePolicy.validate_template(attrs),
         {:ok, version_attrs} <-
           TemplatePolicy.validate_version(Map.put_new(attrs, :title, template_attrs.title), 1) do
      DocumentStore.transaction(context, fn ->
        with {:ok, template} <-
               DocumentStore.insert_template(
                 context,
                 Map.put(template_attrs, :created_by_id, actor_id)
               ),
             {:ok, _event} <-
               audit(
                 context,
                 "template_created",
                 "document_template",
                 template.id,
                 actor_id,
                 now,
                 %{
                   kind: template.kind,
                   title: template.title,
                   requirement: template.requirement
                 }
               ) do
          insert_version(context, template, version_attrs, actor_id, now)
        end
      end)
    end
  end

  @doc """
  Publishes the next version of a document (`attrs`: title, body,
  language, change_kind). A `major` version asks everyone to sign again.
  """
  def publish_version(context, template_id, attrs, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      with {:ok, template} <- active_template(context, template_id, lock: true),
           attrs = Map.put_new(attrs, :title, template.title),
           {:ok, version_attrs} <-
             TemplatePolicy.validate_version(attrs, template.current_version_number + 1) do
        insert_version(context, template, version_attrs, actor_id, now)
      end
    end)
  end

  defp insert_version(context, template, version_attrs, actor_id, now) do
    numbers = TemplatePolicy.next_numbers(template, version_attrs.change_kind)
    id = Ecto.UUID.generate()

    version =
      Map.merge(version_attrs, %{
        id: id,
        template_id: template.id,
        number: numbers.current_version_number,
        published_by_id: actor_id,
        published_at: now
      })

    version = Map.put(version, :content_hash, TemplatePolicy.content_hash(version))

    with {:ok, saved} <- DocumentStore.insert_version(context, version),
         {:ok, template} <-
           DocumentStore.update_template(
             context,
             template.id,
             Map.merge(numbers, %{current_version_id: saved.id, title: saved.title})
           ),
         {:ok, _event} <-
           audit(context, "version_published", "document_template", template.id, actor_id, now, %{
             version_id: saved.id,
             number: saved.number,
             change_kind: saved.change_kind,
             content_hash: saved.content_hash,
             language: saved.language
           }) do
      {:ok, %{template: template, version: saved}}
    end
  end

  @doc "Sets a document `mandatory` or `optional` and audits the change."
  def set_requirement(context, template_id, requirement, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      with {:ok, requirement} <- TemplatePolicy.validate_requirement(requirement),
           {:ok, template} <- active_template(context, template_id, lock: true) do
        if template.requirement == requirement do
          {:ok, template}
        else
          with {:ok, updated} <-
                 DocumentStore.update_template(context, template.id, %{requirement: requirement}),
               {:ok, _event} <-
                 audit(
                   context,
                   "requirement_changed",
                   "document_template",
                   template.id,
                   actor_id,
                   now,
                   %{from: template.requirement, to: requirement}
                 ) do
            {:ok, updated}
          end
        end
      end
    end)
  end

  @doc "Archives a document: no longer offered, required or requested."
  def archive_template(context, template_id, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      with {:ok, template} <- active_template(context, template_id, lock: true),
           {:ok, archived} <-
             DocumentStore.update_template(context, template.id, %{
               status: "archived",
               archived_at: now
             }),
           cancelled = DocumentStore.cancel_requests_for_template(context, template.id, now),
           {:ok, _event} <-
             audit(
               context,
               "template_archived",
               "document_template",
               template.id,
               actor_id,
               now,
               %{
                 cancelled_requests: cancelled
               }
             ) do
        {:ok, archived}
      end
    end)
  end

  defp active_template(context, template_id, opts) do
    case DocumentStore.get_template(context, template_id, opts) do
      %{status: "active"} = template -> {:ok, template}
      %{} -> {:error, :document_archived}
      nil -> {:error, :not_found}
    end
  end

  @doc "Documents; filters: status, requirement."
  def list_templates(context, filters \\ %{}), do: DocumentStore.list_templates(context, filters)

  def get_template(context, id), do: DocumentStore.get_template(context, id, [])

  @doc "A document with its versions (newest first, without bodies)."
  def get_template_with_versions(context, id) do
    case get_template(context, id) do
      nil -> {:error, :not_found}
      template -> {:ok, Map.put(template, :versions, DocumentStore.list_versions(context, id))}
    end
  end

  def get_version(context, id), do: DocumentStore.get_version(context, id)

  @doc "The text a person signs now: `{:ok, %{template, version}}`."
  def current_version(context, template_id) do
    with {:ok, template} <- active_template(context, template_id, []),
         %{} = version <-
           DocumentStore.get_version(context, template.current_version_id) ||
             {:error, :document_not_published} do
      {:ok, %{template: template, version: version}}
    end
  end

  # ── Requests ────────────────────────────────────────────────────────────

  @doc """
  Asks `user_ids` to sign a document. People who already signed the
  required version or have a pending request are skipped. `audience` is
  `person`, `all_clients`, `role` or `package`. Returns `{:ok, %{batch_id,
  requests, skipped}}`; the batch is audited.
  """
  def request_signatures(context, template_id, user_ids, audience, actor_id, %DateTime{} = now) do
    user_ids = Enum.uniq(user_ids)

    DocumentStore.transaction(context, fn ->
      with {:ok, template} <- active_template(context, template_id, []),
           true <- template.current_version_number > 0 || {:error, :document_not_published} do
        signatures = DocumentStore.latest_signatures(context, user_ids, [template.id])

        {to_ask, already_signed} =
          Enum.split_with(user_ids, fn user_id ->
            SignaturePolicy.status(template, Map.get(signatures, {user_id, template.id})) !=
              :signed
          end)

        batch_id = Ecto.UUID.generate()

        rows =
          Enum.map(to_ask, fn user_id ->
            %{
              template_id: template.id,
              user_id: user_id,
              batch_id: batch_id,
              audience: audience,
              requested_by_id: actor_id,
              requested_at: now
            }
          end)

        with {:ok, inserted} <- DocumentStore.insert_requests(context, rows),
             {:ok, _event} <-
               audit(
                 context,
                 "signatures_requested",
                 "document_template",
                 template.id,
                 actor_id,
                 now,
                 %{
                   batch_id: batch_id,
                   audience: audience,
                   recipients: length(user_ids),
                   created: length(inserted),
                   already_signed: length(already_signed)
                 }
               ) do
          {:ok,
           %{
             batch_id: batch_id,
             template: template,
             requests: inserted,
             skipped: length(user_ids) - length(inserted)
           }}
        end
      end
    end)
  end

  @doc "Cancels a pending request."
  def cancel_request(context, request_id, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      case DocumentStore.get_request(context, request_id) do
        nil ->
          {:error, :not_found}

        %{status: "pending"} = request ->
          with {:ok, cancelled} <-
                 DocumentStore.update_request(context, request.id, %{
                   status: "cancelled",
                   closed_at: now
                 }),
               {:ok, _event} <-
                 audit(
                   context,
                   "request_cancelled",
                   "document_signature_request",
                   request.id,
                   actor_id,
                   now,
                   %{template_id: request.template_id},
                   request.user_id
                 ) do
            {:ok, cancelled}
          end

        _closed ->
          {:error, :document_request_closed}
      end
    end)
  end

  @doc "Requests; filters: status, template_id, user_id, batch_id, limit, offset."
  def list_requests(context, filters \\ %{}), do: DocumentStore.list_requests(context, filters)

  # ── A person's documents ────────────────────────────────────────────────

  @doc """
  Every active, published document with the person's status (see
  `MemberDocuments.items/3`).
  """
  def member_items(context, user_id) do
    templates = DocumentStore.list_templates(context, %{status: "active"})
    template_ids = Enum.map(templates, & &1.id)

    signatures =
      context
      |> DocumentStore.latest_signatures([user_id], template_ids)
      |> Map.new(fn {{_user_id, template_id}, signature} -> {template_id, signature} end)

    MemberDocuments.items(
      templates,
      signatures,
      DocumentStore.pending_request_template_ids(context, user_id)
    )
  end

  @doc """
  The status of every active, published document for each of `user_ids`:
  `%{user_id => %{template_id => status}}`.
  """
  def statuses(context, user_ids) do
    templates =
      context
      |> DocumentStore.list_templates(%{status: "active"})
      |> Enum.filter(&(&1.current_version_number > 0))

    signatures =
      DocumentStore.latest_signatures(context, user_ids, Enum.map(templates, & &1.id))

    Map.new(user_ids, fn user_id ->
      {user_id,
       Map.new(templates, fn template ->
         {template.id,
          SignaturePolicy.status(template, Map.get(signatures, {user_id, template.id}))}
       end)}
    end)
  end

  defdelegate health_outstanding(settings, status), to: MemberDocuments

  @doc """
  The booking gate (ADR-252): `:ok` or `{:error, :documents_required,
  %{documents, health_certificate}}`.
  """
  def booking_gate(context, user_id, %Date{} = today) do
    settings = settings(context)

    if settings.block_booking_on_unsigned or settings.block_booking_on_health_certificate do
      items = if settings.block_booking_on_unsigned, do: member_items(context, user_id), else: []

      health =
        if settings.block_booking_on_health_certificate,
          do: health_status(context, user_id, today, settings).status

      MemberDocuments.booking_gate(settings, items, health)
    else
      :ok
    end
  end

  # ── Signing ─────────────────────────────────────────────────────────────

  @doc """
  Signs the current version of a document (ADR-252).

  `params`: version_id, agreed, typed_name and/or drawn_signature.
  `signer`: user_id, display_name, nickname, email. `meta`: ip_address,
  user_agent, business_name, local_signed_at.

  The certificate is rendered and stored first; the signature row is then
  written while the template is locked, so it can only name the version
  that is still current. `{:ok, signature}`.
  """
  def sign(context, template_id, params, signer, meta, %DateTime{} = now) do
    with {:ok, %{template: template, version: version}} <- current_version(context, template_id),
         {:ok, input} <- SignaturePolicy.validate(params, version) do
      store = evidence_store()
      signature_id = Ecto.UUID.generate()

      attrs = %{
        signature_id: signature_id,
        organization_id: context.organization_id,
        template_id: template.id,
        version_id: version.id,
        version_number: version.number,
        content_hash: version.content_hash,
        signed_at: now,
        level: store.level(),
        provider: store.provider(),
        signer: signer,
        typed_name: input.typed_name,
        drawn_signature: input.drawn_signature,
        ip_address: SignaturePolicy.ip_address(meta[:ip_address]),
        user_agent: SignaturePolicy.user_agent(meta[:user_agent])
      }

      {evidence, evidence_hash} = SignaturePolicy.evidence(attrs)

      certificate = %{
        business_name: meta[:business_name],
        local_signed_at: meta[:local_signed_at],
        title: version.title,
        language: version.language,
        body: version.body,
        version_number: version.number,
        evidence: evidence,
        evidence_hash: evidence_hash
      }

      with {:ok, pdf} <- certificate_renderer().render(certificate),
           {:ok, sealed} <- store.seal(context, pdf, evidence),
           {:ok, stored} <- store.store(context, signature_id, sealed) do
        record(context, template.id, version.id, evidence, evidence_hash, stored, now)
      end
    end
  end

  defp record(context, template_id, version_id, evidence, evidence_hash, stored, now) do
    DocumentStore.transaction(context, fn ->
      with {:ok, template} <- active_template(context, template_id, lock: true),
           true <-
             template.current_version_id == version_id || {:error, :document_version_outdated},
           {:ok, signature} <-
             DocumentStore.insert_signature(context, %{
               id: evidence.signature_id,
               template_id: template_id,
               version_id: version_id,
               version_number: evidence.version_number,
               user_id: evidence.signer.user_id,
               signed_at: now,
               level: evidence.level,
               provider: evidence.provider,
               content_hash: evidence.content_hash,
               typed_name: evidence.typed_name,
               drawn_signature: evidence.drawn_signature,
               ip_address: evidence.ip_address,
               user_agent: evidence.user_agent,
               account: evidence.signer,
               evidence_hash: evidence_hash,
               evidence_object_key: stored.key,
               evidence_sha256: stored.sha256,
               evidence_byte_size: stored.byte_size
             }),
           closed =
             DocumentStore.close_requests(context, template_id, evidence.signer.user_id, %{
               signature_id: signature.id,
               closed_at: now
             }) do
        {:ok, Map.put(signature, :closed_request_ids, closed)}
      end
    end)
  end

  def get_signature(context, id), do: DocumentStore.get_signature(context, id)

  @doc "Signatures; filters: template_id, user_id, limit, offset."
  def list_signatures(context, filters \\ %{}),
    do: DocumentStore.list_signatures(context, filters)

  @doc "A short-lived URL of a signature's certificate."
  def evidence_url(context, %{evidence_object_key: key}),
    do: evidence_store().download_url(context, key)

  # ── Health certificates ─────────────────────────────────────────────────

  @doc """
  A person's health certificate status: `%{status, certificate}` with the
  certificate with the latest expiry (or nil).
  """
  def health_status(context, user_id, %Date{} = today, settings \\ nil) do
    settings = settings || settings(context)

    certificate =
      context |> DocumentStore.current_health_certificates([user_id]) |> Map.get(user_id)

    %{
      status:
        HealthCertificatePolicy.status(
          certificate,
          today,
          settings.health_certificate_reminder_days
        ),
      certificate: certificate
    }
  end

  @doc "`%{user_id => %{status, certificate}}` for `user_ids` (or every holder with `:all`)."
  def health_statuses(context, user_ids, %Date{} = today) do
    settings = settings(context)
    current = DocumentStore.current_health_certificates(context, user_ids)
    ids = if user_ids == :all, do: Map.keys(current), else: user_ids

    Map.new(ids, fn user_id ->
      certificate = Map.get(current, user_id)

      {user_id,
       %{
         status:
           HealthCertificatePolicy.status(
             certificate,
             today,
             settings.health_certificate_reminder_days
           ),
         certificate: certificate
       }}
    end)
  end

  def list_health_certificates(context, user_id),
    do: DocumentStore.list_health_certificates(context, user_id)

  def get_health_certificate(context, id), do: DocumentStore.get_health_certificate(context, id)

  @doc """
  Records an uploaded certificate (`attrs`: issued_on, expires_on,
  file_key, content_type, byte_size) and audits it.
  """
  def record_health_certificate(context, user_id, attrs, actor_id, %Date{} = today, now) do
    settings = settings(context)

    with {:ok, dates} <-
           HealthCertificatePolicy.validate_dates(
             attrs[:issued_on],
             attrs[:expires_on],
             today,
             settings.health_certificate_validity_months
           ) do
      DocumentStore.transaction(context, fn ->
        with {:ok, certificate} <-
               DocumentStore.insert_health_certificate(
                 context,
                 Map.merge(dates, %{
                   user_id: user_id,
                   file_key: attrs.file_key,
                   content_type: attrs.content_type,
                   byte_size: attrs.byte_size,
                   uploaded_by_id: actor_id
                 })
               ),
             {:ok, _event} <-
               audit(
                 context,
                 "health_certificate_uploaded",
                 "health_certificate",
                 certificate.id,
                 actor_id,
                 now,
                 %{issued_on: certificate.issued_on, expires_on: certificate.expires_on},
                 user_id
               ) do
          {:ok, certificate}
        end
      end)
    end
  end

  @doc "Deletes a certificate row (the caller deletes the file) and audits it."
  def delete_health_certificate(context, id, actor_id, %DateTime{} = now) do
    DocumentStore.transaction(context, fn ->
      with {:ok, certificate} <- DocumentStore.delete_health_certificate(context, id),
           {:ok, _event} <-
             audit(
               context,
               "health_certificate_deleted",
               "health_certificate",
               certificate.id,
               actor_id,
               now,
               %{},
               certificate.user_id
             ) do
        {:ok, certificate}
      end
    end)
  end

  @doc "Certificates whose holders should be reminded today (box requires certificates)."
  def health_reminders_due(context, %Date{} = today) do
    settings = settings(context)

    if settings.health_certificate_required do
      until = Date.add(today, settings.health_certificate_reminder_days)

      context
      |> DocumentStore.health_certificates_expiring(today, until)
      |> Enum.filter(
        &HealthCertificatePolicy.reminder_due?(
          &1,
          today,
          settings.health_certificate_reminder_days
        )
      )
    else
      []
    end
  end

  def mark_health_reminded(context, certificate),
    do: DocumentStore.mark_health_reminded(context, certificate.id, certificate.expires_on)

  # ── Audit ───────────────────────────────────────────────────────────────

  @doc "Appends an audit event."
  def audit(
        context,
        action,
        subject_type,
        subject_id,
        actor_id,
        %DateTime{} = now,
        details,
        subject_user_id \\ nil
      ) do
    DocumentStore.insert_audit_event(context, %{
      action: action,
      subject_type: subject_type,
      subject_id: subject_id,
      subject_user_id: subject_user_id,
      actor_id: actor_id,
      details: details,
      occurred_at: now
    })
  end

  @doc "Audit events; filters: subject_id, action, limit, offset."
  def list_audit_events(context, filters \\ %{}),
    do: DocumentStore.list_audit_events(context, filters)

  # ── Tenant data (ADR-117) ───────────────────────────────────────────────

  def tenant_data_policy, do: TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  @doc "Versions, signatures and audit events are insert-only; the store lifts that for the purge."
  def purge_tenant_data(%{organization_id: organization_id} = context)
      when is_binary(organization_id),
      do: DocumentStore.purge(context)

  def purge_tenant_data(_context), do: {:error, :organization_context_required}
end
