defmodule Palee.DocumentsTest do
  @moduledoc """
  ADR-252 end to end through the Documents context, its application services
  and the database, with Row Level Security enforced: versions and their
  audit, requests to one person or in bulk, signing with a stored PDF
  certificate, re-signing after a major version, health certificates and
  their reminders, tenant isolation and the purge.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Ecto.Query
  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 2]

  alias Palee.Application.Documents.{
    DocumentsAdmin,
    HealthCertificateReminders,
    HealthCertificatesAdmin,
    MyDocuments
  }

  alias Palee.{Documents, Finance, Repo}
  alias Palee.Notifications.Notification
  alias Palee.TestSupport.MemoryObjectStore

  @now ~U[2027-02-08 10:00:00.000000Z]
  @pdf "%PDF-1.7\n%âãÏÓ\n1 0 obj\n<<>>\nendobj\n"

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {client, client_context} = bypass_rls(fn -> member_context(organization, :member) end)

    %{
      organization: organization,
      owner: owner,
      context: context,
      client: client,
      client_context: client_context
    }
  end

  defp waiver(context, extra \\ %{}) do
    {:ok, %{template: template, version: version}} =
      DocumentsAdmin.create_template(
        context,
        Map.merge(
          %{
            kind: "waiver",
            title: "Απαλλαγή ευθύνης",
            requirement: "mandatory",
            body: "Κείμενο v1"
          },
          extra
        ),
        @now
      )

    {template, version}
  end

  defp sign(client_context, template_id, version_id, extra \\ %{}) do
    MyDocuments.sign(
      client_context,
      template_id,
      Map.merge(%{version_id: version_id, agreed: true, typed_name: "Μαρία Παπαδοπούλου"}, extra),
      %{
        ip_address: {203, 0, 113, 7},
        user_agent: "Mozilla/5.0 (Test)",
        account: %{nickname: "Μαρία", handle: "maria", email: "maria@example.com"}
      },
      @now
    )
  end

  defp notifications(user_id, type) do
    bypass_rls(fn ->
      Repo.all(from n in Notification, where: n.user_id == ^user_id and n.type == ^type)
    end)
  end

  describe "documents and versions" do
    test "publishing and requirement changes are audited; versions keep their text", %{
      context: context,
      owner: owner
    } do
      {template, v1} = waiver(context)
      assert v1.number == 1 and v1.change_kind == "major"

      assert {:ok, %{template: %{current_version_number: 2, required_version_number: 1}}} =
               DocumentsAdmin.publish_version(
                 context,
                 template.id,
                 %{body: "Κείμενο v1 (τυπογραφικό)", change_kind: "minor"},
                 @now
               )

      assert {:ok, %{template: %{requirement: "optional"}}} =
               DocumentsAdmin.set_requirement(
                 context,
                 template.id,
                 %{requirement: "optional"},
                 @now
               )

      actions =
        context
        |> Documents.list_audit_events(%{subject_id: template.id})
        |> Map.fetch!(:events)
        |> Enum.map(& &1.action)
        |> Enum.sort()

      assert actions ==
               ~w(requirement_changed template_created version_published version_published)

      assert %{actor_id: actor} =
               context
               |> Documents.list_audit_events(%{action: "requirement_changed"})
               |> Map.fetch!(:events)
               |> hd()

      assert actor == owner.id

      assert {:ok, %{versions: [%{number: 2}, %{number: 1}]}} =
               Documents.get_template_with_versions(context, template.id)

      assert Documents.get_version(context, v1.id).body == "Κείμενο v1"

      {:ok, version_id} = Ecto.UUID.dump(v1.id)

      bypass_rls(fn ->
        assert_raise Postgrex.Error, ~r/insert-only/, fn ->
          Repo.query!("UPDATE document_versions SET body = 'x' WHERE id = $1", [version_id])
        end
      end)
    end

    test "an archived document cannot be published, signed or requested",
         %{context: context} = ctx do
      {template, version} = waiver(context)
      assert {:ok, _} = DocumentsAdmin.archive_template(context, template.id, @now)

      assert {:error, :document_archived} =
               DocumentsAdmin.publish_version(context, template.id, %{body: "x"}, @now)

      assert {:error, :document_archived} = sign(ctx.client_context, template.id, version.id)

      assert {:error, :document_archived} =
               DocumentsAdmin.request_signatures(
                 context,
                 template.id,
                 %{audience: "all_clients"},
                 @now
               )
    end
  end

  describe "signature requests" do
    test "one person, all clients, a role and a package; each new request notifies", %{
      organization: organization,
      context: context,
      client: client
    } do
      {template, _version} = waiver(context)
      {athlete, _} = bypass_rls(fn -> member_context(organization, :athlete) end)
      {coach, _} = bypass_rls(fn -> member_context(organization, :coach) end)

      assert {:error, {:invalid_fields, %{user_id: "not_a_client"}}} =
               DocumentsAdmin.request_signatures(
                 context,
                 template.id,
                 %{audience: "person", user_id: coach.id},
                 @now
               )

      assert {:ok, %{created: 1, recipients: 1}} =
               DocumentsAdmin.request_signatures(
                 context,
                 template.id,
                 %{audience: "person", user_id: client.id},
                 @now
               )

      # Bulk: the pending request of the client is not duplicated.
      assert {:ok, %{created: 1, skipped: 1, recipients: 2}} =
               DocumentsAdmin.request_signatures(
                 context,
                 template.id,
                 %{audience: "all_clients"},
                 @now
               )

      assert [_] = notifications(client.id, :document_signature_requested)
      assert [notification] = notifications(athlete.id, :document_signature_requested)
      assert notification.payload["template_id"] == template.id
      assert notifications(coach.id, :document_signature_requested) == []

      {other, _version} = waiver(context, %{title: "Όροι", kind: "terms"})

      assert {:ok, %{recipients: 1, created: 1}} =
               DocumentsAdmin.request_signatures(
                 context,
                 other.id,
                 %{audience: "role", role: "athlete"},
                 @now
               )

      assert {:error, {:invalid_fields, %{role: "invalid"}}} =
               DocumentsAdmin.request_signatures(
                 context,
                 other.id,
                 %{audience: "role", role: "coach"},
                 @now
               )

      {:ok, package} =
        Finance.create_package(context, %{name: "Unlimited", package_type: "class_pack"})

      {:ok, membership} =
        Finance.upsert_membership(context, client.id, %{
          user_type_snapshot: "member",
          status: "active",
          signup_source: "admin_created"
        })

      {:ok, _subscription} = Finance.assign_package(context, membership.id, package.id, %{})

      assert {:ok, %{recipients: 1, requests: [%{user_id: user_id}]}} =
               DocumentsAdmin.request_signatures(
                 context,
                 other.id,
                 %{audience: "package", package_id: package.id},
                 # The subscription runs from today.
                 DateTime.utc_now()
               )

      assert user_id == client.id

      assert {:ok, %{requests: requests}} =
               {:ok,
                Documents.list_requests(context, %{template_id: other.id, status: "pending"})}

      assert length(requests) == 2
    end
  end

  describe "signing" do
    test "stores the PDF certificate with its evidence and closes the request", %{
      context: context,
      client: client,
      client_context: client_context
    } do
      {template, version} = waiver(context)

      {:ok, _} =
        DocumentsAdmin.request_signatures(
          context,
          template.id,
          %{audience: "person", user_id: client.id},
          @now
        )

      assert %{outstanding: 1, documents: [%{status: "unsigned", requested: true}]} =
               MyDocuments.overview(client_context, @now)

      assert {:error, :documents_required, %{documents: [%{template_id: id}]}} =
               Documents.booking_gate(context, client.id, ~D[2027-02-08])

      assert id == template.id

      assert {:error, {:invalid_fields, %{agreed: "required"}}} =
               sign(client_context, template.id, version.id, %{agreed: false})

      drawn = %{"width" => 300, "height" => 100, "strokes" => [[[10, 10], [50, 60]]]}

      assert {:ok, %{signature: signature}} =
               sign(client_context, template.id, version.id, %{drawn_signature: drawn})

      stored = Documents.get_signature(context, signature.id)
      assert stored.user_id == client.id
      assert stored.ip_address == "203.0.113.7"
      assert stored.content_hash == version.content_hash
      assert stored.typed_name == "Μαρία Παπαδοπούλου"
      assert stored.account["email"] == "maria@example.com"
      assert stored.level == "simple"
      assert stored.evidence_object_key =~ "documents/evidence/#{signature.id}.pdf"

      assert {:ok, pdf} = MemoryObjectStore.get(:documents, stored.evidence_object_key)
      assert "%PDF-1.7" <> _ = pdf
      assert stored.evidence_sha256 == Base.encode16(:crypto.hash(:sha256, pdf), case: :lower)

      assert %{outstanding: 0, documents: [%{status: "signed", requested: false}]} =
               MyDocuments.overview(client_context, @now)

      assert [%{status: "signed"}] =
               Documents.list_requests(context, %{template_id: template.id}).requests

      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])
      assert {:ok, %{url: _url}} = MyDocuments.evidence(client_context, signature.id)

      {:ok, signature_id} = Ecto.UUID.dump(signature.id)

      bypass_rls(fn ->
        assert_raise Postgrex.Error, ~r/insert-only/, fn ->
          Repo.query!("DELETE FROM document_signatures WHERE id = $1", [signature_id])
        end
      end)
    end

    test "a major version asks to sign again; a minor one does not", %{
      context: context,
      client: client,
      client_context: client_context
    } do
      {template, v1} = waiver(context)
      {:ok, _} = sign(client_context, template.id, v1.id)

      {:ok, %{version: v2}} =
        DocumentsAdmin.publish_version(
          context,
          template.id,
          %{body: "v2", change_kind: "minor"},
          @now
        )

      assert %{outstanding: 0} = MyDocuments.overview(client_context, @now)
      # The old version can no longer be signed.
      assert {:error, :document_version_outdated} = sign(client_context, template.id, v1.id)

      {:ok, %{version: v3}} =
        DocumentsAdmin.publish_version(
          context,
          template.id,
          %{body: "v3", change_kind: "major"},
          @now
        )

      assert %{outstanding: 1, documents: [%{status: "resign_required"}]} =
               MyDocuments.overview(client_context, @now)

      assert {:error, :documents_required, %{documents: [%{reason: "resign_required"}]}} =
               Documents.booking_gate(context, client.id, ~D[2027-02-08])

      refute v2.id == v3.id
      assert {:ok, _} = sign(client_context, template.id, v3.id)
      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])
    end

    test "optional documents are offered and never block; the gate can be turned off", %{
      context: context,
      client: client
    } do
      {_template, _version} = waiver(context, %{requirement: "optional"})
      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])

      {_mandatory, _version} = waiver(context, %{title: "Όροι", kind: "terms"})

      assert {:error, :documents_required, _} =
               Documents.booking_gate(context, client.id, ~D[2027-02-08])

      {:ok, _} = DocumentsAdmin.save_settings(context, %{block_booking_on_unsigned: false}, @now)
      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])

      assert [%{action: "settings_changed"}] =
               Documents.list_audit_events(context, %{action: "settings_changed"}).events
    end
  end

  describe "health certificates" do
    defp upload(client_context, issued_on, body \\ @pdf) do
      {:ok, upload} =
        MyDocuments.request_health_upload(client_context, %{content_type: "application/pdf"})

      :ok = MemoryObjectStore.put_object(:documents, upload.file_key, body, "application/pdf")

      MyDocuments.complete_health_upload(
        client_context,
        %{
          file_key: upload.file_key,
          content_type: "application/pdf",
          issued_on: issued_on
        },
        @now
      )
    end

    test "a member uploads their certificate; the file is checked and dated", ctx do
      %{client_context: client_context, context: context, client: client} = ctx

      assert {:error, :health_certificate_file_invalid} =
               upload(client_context, "2027-01-10", <<0x89, "PNG", 13, 10>>)

      assert {:ok, %{health_certificate: certificate}} = upload(client_context, "2027-01-10")
      assert certificate.expires_on == ~D[2028-01-10]

      assert %{health_certificate: %{status: "valid", certificate: %{id: id}}} =
               MyDocuments.overview(client_context, @now)

      assert id == certificate.id

      # Another member's key is refused.
      {:ok, upload} =
        MyDocuments.request_health_upload(client_context, %{content_type: "application/pdf"})

      assert {:error, :document_key_forbidden} =
               MyDocuments.complete_health_upload(
                 ctx.context,
                 %{
                   file_key: upload.file_key,
                   content_type: "application/pdf",
                   issued_on: "2027-01-10"
                 },
                 @now
               )

      assert {:ok, %{url: _}} = MyDocuments.health_file(client_context, certificate.id, @now)

      assert [%{action: "health_certificate_viewed", subject_user_id: subject}] =
               Documents.list_audit_events(context, %{action: "health_certificate_viewed"}).events

      assert subject == client.id

      file_key = Documents.get_health_certificate(context, id).file_key
      assert {:ok, _file} = MemoryObjectStore.get(:documents, file_key)

      assert {:ok, %{health_certificate: %{id: ^id}}} =
               MyDocuments.delete_health_certificate(client_context, certificate.id, @now)

      assert MemoryObjectStore.get(:documents, file_key) == :error

      assert %{health_certificate: %{status: "missing"}} =
               MyDocuments.overview(client_context, @now)
    end

    test "staff with the capability see files; coaches see only valid or expired", ctx do
      %{
        organization: organization,
        context: context,
        client: client,
        client_context: client_context
      } =
        ctx

      {:ok, _} = upload(client_context, "2026-02-20")
      {coach, coach_context} = bypass_rls(fn -> member_context(organization, :coach) end)
      assert %{health_certificates: []} = HealthCertificatesAdmin.list(coach_context, %{}, @now)

      {:ok, _} =
        Palee.Coaching.start_relationship(context, %{
          coach_user_id: coach.id,
          client_user_id: client.id,
          origin: "assigned"
        })

      assert %{health_certificates: [row]} = HealthCertificatesAdmin.list(context, %{}, @now)
      assert row.user_id == client.id
      assert row.status == "expiring"
      assert row.certificate.expires_on == ~D[2027-02-20]

      assert %{health_certificates: [coach_row]} =
               HealthCertificatesAdmin.list(coach_context, %{}, @now)

      assert coach_row.status == "valid"
      assert coach_row.certificate == nil
    end

    test "reminders go out once per expiry when the box requires certificates", ctx do
      %{context: context, client: client, client_context: client_context} = ctx
      {:ok, _} = upload(client_context, "2026-02-20")

      assert HealthCertificateReminders.remind(context, @now) == 0

      {:ok, _} = DocumentsAdmin.save_settings(context, %{health_certificate_required: true}, @now)
      assert HealthCertificateReminders.remind(context, @now) == 1
      assert HealthCertificateReminders.remind(context, @now) == 0
      assert [_] = notifications(client.id, :health_certificate_expiring)
    end

    test "the booking block for certificates is off by default and opt-in", ctx do
      %{context: context, client: client, client_context: client_context} = ctx
      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])

      {:ok, %{settings: settings}} =
        DocumentsAdmin.save_settings(context, %{block_booking_on_health_certificate: true}, @now)

      assert settings.health_certificate_required

      assert {:error, :documents_required, %{health_certificate: "missing", documents: []}} =
               Documents.booking_gate(context, client.id, ~D[2027-02-08])

      assert %{outstanding: 1} = MyDocuments.overview(client_context, @now)
      {:ok, _} = upload(client_context, "2027-01-10")
      assert :ok = Documents.booking_gate(context, client.id, ~D[2027-02-08])
    end
  end

  describe "tenant data" do
    test "another gym sees nothing; the purge removes every row", %{
      context: context,
      client_context: client_context
    } do
      {template, version} = waiver(context)
      {:ok, _} = sign(client_context, template.id, version.id)
      {_org, _owner, other} = bypass_rls(fn -> organization_fixture() end)

      assert Documents.get_template(other, template.id) == nil
      assert Documents.list_templates(other) == []
      assert Documents.list_signatures(other).total == 0
      assert Documents.list_audit_events(other).events == []

      assert {:ok, deleted} = Documents.purge_tenant_data(context)
      assert deleted["document_signatures"] == 1
      assert deleted["document_versions"] == 1
      assert deleted["document_templates"] == 1
      assert Documents.list_templates(context) == []
    end
  end
end
