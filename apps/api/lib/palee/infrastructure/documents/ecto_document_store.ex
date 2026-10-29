defmodule Palee.Infrastructure.Documents.EctoDocumentStore do
  @moduledoc "Ecto adapter of the Documents store (ADR-252)."

  @behaviour Palee.Documents.Ports.DocumentStore

  import Ecto.Query

  alias Palee.Documents.{
    AuditEvent,
    HealthCertificate,
    Settings,
    Signature,
    SignatureRequest,
    Template,
    Version
  }

  alias Palee.Repo

  @max_page 200

  @impl true
  def transaction(_context, fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Settings ──────────────────────────────────────────────────────────────

  @impl true
  def get_settings(%{organization_id: organization_id}) do
    Settings |> where([s], s.organization_id == ^organization_id) |> Repo.one() |> to_map()
  end

  @impl true
  def save_settings(%{organization_id: organization_id}, attrs) do
    case Repo.one(from s in Settings, where: s.organization_id == ^organization_id) do
      nil -> %Settings{organization_id: organization_id}
      settings -> settings
    end
    |> Settings.changeset(attrs)
    |> Repo.insert_or_update()
    |> map_result()
  end

  # ── Templates and versions ────────────────────────────────────────────────

  @impl true
  def insert_template(%{organization_id: organization_id}, attrs) do
    %Template{organization_id: organization_id}
    |> Template.changeset(attrs)
    |> Repo.insert()
    |> map_result()
  end

  @impl true
  def update_template(context, id, attrs) do
    case template(context, id) |> Repo.one() do
      nil -> {:error, :not_found}
      template -> template |> Template.changeset(attrs) |> Repo.update() |> map_result()
    end
  end

  @impl true
  def get_template(context, id, opts) do
    if Keyword.get(opts, :lock, false),
      do: context |> template(id) |> lock("FOR UPDATE") |> Repo.one() |> to_map(),
      else: context |> template(id) |> Repo.one() |> to_map()
  end

  defp template(%{organization_id: organization_id}, id) do
    if uuid?(id),
      do: where(Template, [t], t.organization_id == ^organization_id and t.id == ^id),
      else: where(Template, [t], false)
  end

  @impl true
  def list_templates(%{organization_id: organization_id}, filters) do
    Template
    |> where([t], t.organization_id == ^organization_id)
    |> filter(:status, filters[:status])
    |> filter(:requirement, filters[:requirement])
    |> order_by([t], asc: t.status, asc: t.title, asc: t.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def insert_version(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Version.insert_changeset()
    |> Repo.insert()
    |> map_result()
  end

  @impl true
  def get_version(%{organization_id: organization_id}, id) do
    if uuid?(id) do
      Version
      |> where([v], v.organization_id == ^organization_id and v.id == ^id)
      |> Repo.one()
      |> to_map()
    end
  end

  @impl true
  def list_versions(%{organization_id: organization_id}, template_id) do
    Version
    |> where([v], v.organization_id == ^organization_id and v.template_id == ^template_id)
    |> order_by([v], desc: v.number)
    |> select([v], %{
      id: v.id,
      template_id: v.template_id,
      number: v.number,
      title: v.title,
      language: v.language,
      change_kind: v.change_kind,
      content_hash: v.content_hash,
      published_by_id: v.published_by_id,
      published_at: v.published_at
    })
    |> Repo.all()
  end

  # ── Requests ──────────────────────────────────────────────────────────────

  @impl true
  def insert_requests(_context, []), do: {:ok, []}

  def insert_requests(%{organization_id: organization_id}, rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.take(SignatureRequest.fields())
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          organization_id: organization_id,
          status: "pending",
          inserted_at: now,
          updated_at: now
        })
      end)

    {_count, inserted} =
      Repo.insert_all(SignatureRequest, entries,
        on_conflict: :nothing,
        conflict_target:
          {:unsafe_fragment, "(template_id, user_id) WHERE status = 'pending'"},
        returning: true
      )

    {:ok, Enum.map(inserted, &to_map/1)}
  end

  @impl true
  def get_request(%{organization_id: organization_id}, id) do
    if uuid?(id) do
      SignatureRequest
      |> where([r], r.organization_id == ^organization_id and r.id == ^id)
      |> Repo.one()
      |> to_map()
    end
  end

  @impl true
  def update_request(%{organization_id: organization_id}, id, attrs) do
    case Repo.one(
           from r in SignatureRequest, where: r.organization_id == ^organization_id and r.id == ^id
         ) do
      nil -> {:error, :not_found}
      request -> request |> SignatureRequest.changeset(attrs) |> Repo.update() |> map_result()
    end
  end

  @impl true
  def list_requests(%{organization_id: organization_id}, filters) do
    query =
      SignatureRequest
      |> where([r], r.organization_id == ^organization_id)
      |> filter(:status, filters[:status])
      |> filter(:template_id, filters[:template_id])
      |> filter(:user_id, filters[:user_id])
      |> filter(:batch_id, filters[:batch_id])

    requests =
      query
      |> order_by([r], desc: r.requested_at, desc: r.id)
      |> page(filters)
      |> Repo.all()
      |> Enum.map(&to_map/1)

    %{requests: requests, total: Repo.aggregate(query, :count)}
  end

  @impl true
  def pending_request_template_ids(%{organization_id: organization_id}, user_id) do
    SignatureRequest
    |> where([r], r.organization_id == ^organization_id and r.user_id == ^user_id)
    |> where([r], r.status == "pending")
    |> select([r], r.template_id)
    |> Repo.all()
  end

  @impl true
  def close_requests(%{organization_id: organization_id}, template_id, user_id, attrs) do
    {_count, ids} =
      SignatureRequest
      |> where([r], r.organization_id == ^organization_id and r.template_id == ^template_id)
      |> where([r], r.user_id == ^user_id and r.status == "pending")
      |> select([r], r.id)
      |> Repo.update_all(
        set: [
          status: "signed",
          signature_id: attrs.signature_id,
          closed_at: attrs.closed_at,
          updated_at: attrs.closed_at
        ]
      )

    ids
  end

  @impl true
  def cancel_requests_for_template(%{organization_id: organization_id}, template_id, now) do
    {count, _} =
      SignatureRequest
      |> where([r], r.organization_id == ^organization_id and r.template_id == ^template_id)
      |> where([r], r.status == "pending")
      |> Repo.update_all(set: [status: "cancelled", closed_at: now, updated_at: now])

    count
  end

  # ── Signatures ────────────────────────────────────────────────────────────

  @impl true
  def insert_signature(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> Signature.insert_changeset()
    |> Repo.insert()
    |> map_result()
  end

  @impl true
  def get_signature(%{organization_id: organization_id}, id) do
    if uuid?(id) do
      Signature
      |> where([s], s.organization_id == ^organization_id and s.id == ^id)
      |> Repo.one()
      |> to_map()
    end
  end

  @impl true
  def list_signatures(%{organization_id: organization_id}, filters) do
    query =
      Signature
      |> where([s], s.organization_id == ^organization_id)
      |> filter(:template_id, filters[:template_id])
      |> filter(:user_id, filters[:user_id])

    signatures =
      query
      |> order_by([s], desc: s.signed_at, desc: s.id)
      |> page(filters)
      |> Repo.all()
      |> Enum.map(&to_map/1)

    %{signatures: signatures, total: Repo.aggregate(query, :count)}
  end

  @impl true
  def latest_signatures(_context, [], _template_ids), do: %{}
  def latest_signatures(_context, _user_ids, []), do: %{}

  def latest_signatures(%{organization_id: organization_id}, user_ids, template_ids) do
    Signature
    |> where([s], s.organization_id == ^organization_id and s.template_id in ^template_ids)
    |> then(fn query ->
      if user_ids == :all, do: query, else: where(query, [s], s.user_id in ^user_ids)
    end)
    |> distinct([s], [s.user_id, s.template_id])
    # The signature of the newest version counts (then the latest one).
    |> order_by([s],
      asc: s.user_id,
      asc: s.template_id,
      desc: s.version_number,
      desc: s.signed_at,
      desc: s.id
    )
    |> Repo.all()
    |> Map.new(fn signature -> {{signature.user_id, signature.template_id}, to_map(signature)} end)
  end

  # ── Audit ─────────────────────────────────────────────────────────────────

  @impl true
  def insert_audit_event(%{organization_id: organization_id}, attrs) do
    attrs
    |> Map.put(:organization_id, organization_id)
    |> AuditEvent.insert_changeset()
    |> Repo.insert()
    |> map_result()
  end

  @impl true
  def list_audit_events(%{organization_id: organization_id}, filters) do
    query =
      AuditEvent
      |> where([e], e.organization_id == ^organization_id)
      |> filter(:subject_id, filters[:subject_id])
      |> filter(:action, filters[:action])

    events =
      query
      |> order_by([e], desc: e.occurred_at, desc: e.id)
      |> page(filters)
      |> Repo.all()
      |> Enum.map(&to_map/1)

    %{events: events, total: Repo.aggregate(query, :count)}
  end

  # ── Health certificates ───────────────────────────────────────────────────

  @impl true
  def insert_health_certificate(%{organization_id: organization_id}, attrs) do
    %HealthCertificate{organization_id: organization_id}
    |> HealthCertificate.changeset(attrs)
    |> Repo.insert()
    |> map_result()
  end

  @impl true
  def get_health_certificate(%{organization_id: organization_id}, id) do
    if uuid?(id) do
      HealthCertificate
      |> where([c], c.organization_id == ^organization_id and c.id == ^id)
      |> Repo.one()
      |> to_map()
    end
  end

  @impl true
  def delete_health_certificate(%{organization_id: organization_id}, id) do
    case Repo.one(
           from c in HealthCertificate,
             where: c.organization_id == ^organization_id and c.id == ^id
         ) do
      nil -> {:error, :not_found}
      certificate -> certificate |> Repo.delete() |> map_result()
    end
  end

  @impl true
  def current_health_certificates(_context, []), do: %{}

  def current_health_certificates(%{organization_id: organization_id}, user_ids) do
    HealthCertificate
    |> where([c], c.organization_id == ^organization_id)
    |> then(fn query ->
      if user_ids == :all, do: query, else: where(query, [c], c.user_id in ^user_ids)
    end)
    |> distinct([c], c.user_id)
    |> order_by([c], asc: c.user_id, desc: c.expires_on, desc: c.inserted_at)
    |> Repo.all()
    |> Map.new(&{&1.user_id, to_map(&1)})
  end

  @impl true
  def list_health_certificates(%{organization_id: organization_id}, user_id) do
    HealthCertificate
    |> where([c], c.organization_id == ^organization_id and c.user_id == ^user_id)
    |> order_by([c], desc: c.expires_on, desc: c.inserted_at)
    |> Repo.all()
    |> Enum.map(&to_map/1)
  end

  @impl true
  def health_certificates_expiring(context, today, until) do
    context
    |> current_health_certificates(:all)
    |> Map.values()
    |> Enum.filter(fn certificate ->
      Date.compare(certificate.expires_on, today) == :gt and
        Date.compare(certificate.expires_on, until) != :gt and
        certificate.reminded_for != certificate.expires_on
    end)
  end

  @impl true
  def mark_health_reminded(%{organization_id: organization_id}, id, date) do
    HealthCertificate
    |> where([c], c.organization_id == ^organization_id and c.id == ^id)
    |> Repo.update_all(set: [reminded_for: date, updated_at: DateTime.utc_now()])

    :ok
  end

  # ── Purge ─────────────────────────────────────────────────────────────────

  @impl true
  def purge(%{organization_id: organization_id}) do
    Repo.transaction(fn ->
      Repo.query!("SELECT set_config('palee.documents_purge', 'on', true)")

      Map.new(
        [
          {"health_certificates", HealthCertificate},
          {"document_audit_events", AuditEvent},
          {"document_signature_requests", SignatureRequest},
          {"document_signatures", Signature},
          {"document_versions", Version},
          {"document_templates", Template},
          {"document_settings", Settings}
        ],
        fn {table, schema} ->
          {count, _} =
            schema |> where([r], r.organization_id == ^organization_id) |> Repo.delete_all()

          {table, count}
        end
      )
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [r], field(r, ^field) == ^value)

  defp page(query, filters) do
    limit = filters |> Map.get(:limit, 50) |> min(@max_page) |> max(1)
    offset = filters |> Map.get(:offset, 0) |> max(0)
    query |> limit(^limit) |> offset(^offset)
  end

  defp uuid?(id), do: is_binary(id) and match?({:ok, _}, Ecto.UUID.cast(id))

  defp map_result({:ok, record}), do: {:ok, to_map(record)}
  defp map_result({:error, %Ecto.Changeset{} = changeset}), do: {:error, changeset_error(changeset)}

  defp changeset_error(changeset) do
    {:invalid_fields,
     Map.new(changeset.errors, fn {field, {message, _opts}} -> {field, message} end)}
  end

  defp to_map(nil), do: nil

  defp to_map(%_{} = record),
    do: record |> Map.from_struct() |> Map.drop([:__meta__])
end
