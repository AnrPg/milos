defmodule PaleeWeb.DocumentsControllerTest do
  @moduledoc """
  ADR-252 over HTTP: staff with the settings or memberships capability
  manage documents and requests; clients read, sign and download their
  certificates; health certificate files need their own capability, coaches
  see only valid or expired; the booking endpoint answers
  `documents_required` with the list.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Organizations, Repo}
  alias Palee.TestSupport.MemoryObjectStore

  @pdf "%PDF-1.7\n1 0 obj\n<<>>\nendobj\n"

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:palee, Oban), :testing, :manual)}
    )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    person = fn role ->
      user = if role == :owner, do: admin_fixture(), else: user_fixture()
      {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, role)
      {user, put_bearer_token(conn, user)}
    end

    {owner_user, owner} = person.(:owner)
    {_desk_user, desk} = person.(:front_desk)
    {coach_user, coach} = person.(:coach)
    {client_user, client} = person.(:member)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner_user, Organizations.legacy_organization_slug())

    slug = Organizations.legacy_organization_slug()

    %{
      context: context,
      owner_user: owner_user,
      owner: owner,
      desk: desk,
      coach: coach,
      coach_user: coach_user,
      client: client,
      client_user: client_user,
      admin: "/api/org/#{slug}/admin/documents",
      me: "/api/org/#{slug}/me/documents",
      org: "/api/org/#{slug}"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("user-agent", "Mozilla/5.0 (Test)")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp get_json(conn, path), do: conn |> recycle() |> get(path)

  defp create_waiver(ctx, requirement \\ "mandatory") do
    ctx.owner
    |> send_json(:post, "#{ctx.admin}/templates", %{
      "kind" => "waiver",
      "title" => "Απαλλαγή ευθύνης",
      "requirement" => requirement,
      "body" => "Κείμενο",
      "language" => "el"
    })
    |> json_response(201)
  end

  test "staff create, publish and request; front desk and coaches cannot manage", ctx do
    assert %{"template" => template, "version" => %{"number" => 1, "change_kind" => "major"}} =
             create_waiver(ctx)

    assert %{"version" => %{"number" => 2}} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/templates/#{template["id"]}/versions", %{
               "body" => "Κείμενο 2",
               "change_kind" => "minor"
             })
             |> json_response(201)

    assert %{"template" => %{"requirement" => "optional"}} =
             ctx.owner
             |> send_json(:put, "#{ctx.admin}/templates/#{template["id"]}/requirement", %{
               "requirement" => "optional"
             })
             |> json_response(200)

    assert %{"created" => 1} =
             ctx.owner
             |> send_json(:post, "#{ctx.admin}/templates/#{template["id"]}/requests", %{
               "audience" => "person",
               "user_id" => ctx.client_user.id
             })
             |> json_response(201)

    assert %{"templates" => [row], "clients" => clients} =
             ctx.owner |> get_json("#{ctx.admin}/outstanding") |> json_response(200)

    assert clients == row["signed"] + row["outstanding"]

    assert row["template_id"] == template["id"]
    assert row["outstanding"] == length(row["clients"])
    assert row["signed"] == 0

    assert %{"status" => "unsigned"} =
             Enum.find(row["clients"], &(&1["user_id"] == ctx.client_user.id))

    assert %{"starters" => starters} =
             ctx.owner |> get_json("#{ctx.admin}/starters?language=el") |> json_response(200)

    assert length(starters) == 4 and Enum.all?(starters, & &1["legal_review_required"])

    for staff <- [ctx.desk, ctx.coach] do
      assert staff
             |> send_json(:post, "#{ctx.admin}/templates", %{
               "kind" => "other",
               "title" => "x",
               "body" => "x"
             })
             |> json_response(403)

      assert staff |> get_json("#{ctx.admin}/settings") |> json_response(403)
    end

    assert ctx.coach |> get_json("#{ctx.admin}/outstanding") |> json_response(403)

    # Front desk asks clients to sign and sees who has not (product owner,
    # 2026-10-29), but never writes documents or opens the evidence PDF.
    assert %{"templates" => [_]} =
             ctx.desk |> get_json("#{ctx.admin}/outstanding") |> json_response(200)

    assert %{"skipped" => 1, "created" => 0} =
             ctx.desk
             |> send_json(:post, "#{ctx.admin}/templates/#{template["id"]}/requests", %{
               "audience" => "person",
               "user_id" => ctx.client_user.id
             })
             |> json_response(201)

    assert ctx.desk
           |> send_json(:put, "#{ctx.admin}/templates/#{template["id"]}/requirement", %{
             "requirement" => "mandatory"
           })
           |> json_response(403)

    assert %{"events" => events} =
             ctx.owner |> get_json("#{ctx.admin}/audit") |> json_response(200)

    assert "requirement_changed" in Enum.map(events, & &1["action"])
  end

  test "a client reads, signs and downloads the certificate; booking waits for the signature",
       ctx do
    %{"template" => template, "version" => version} = create_waiver(ctx)

    slot =
      slot_fixture(workout_fixture(ctx.owner_user, %{tenant_context: ctx.context}), %{
        tenant_context: ctx.context
      })

    assert %{"code" => "documents_required", "params" => %{"documents" => [blocking]}} =
             ctx.client
             |> send_json(:post, "#{ctx.org}/bookings", %{"slot_id" => slot.id})
             |> json_response(409)

    assert blocking["template_id"] == template["id"]

    assert %{"outstanding" => 1, "documents" => [%{"status" => "unsigned"}]} =
             ctx.client |> get_json(ctx.me) |> json_response(200)

    assert %{"version" => %{"body" => "Κείμενο", "content_hash" => hash}} =
             ctx.client |> get_json("#{ctx.me}/#{template["id"]}") |> json_response(200)

    assert hash == version["content_hash"]

    assert %{"code" => "validation_failed"} =
             ctx.client
             |> send_json(:post, "#{ctx.me}/#{template["id"]}/sign", %{
               "version_id" => version["id"],
               "agreed" => false,
               "typed_name" => "Μαρία"
             })
             |> json_response(422)

    assert %{"signature" => signature} =
             ctx.client
             |> send_json(:post, "#{ctx.me}/#{template["id"]}/sign", %{
               "version_id" => version["id"],
               "agreed" => true,
               "typed_name" => "Μαρία Παπαδοπούλου",
               "drawn_signature" => %{
                 "width" => 200,
                 "height" => 80,
                 "strokes" => [[[1, 1], [20, 30]]]
               }
             })
             |> json_response(201)

    assert %{"url" => url} =
             ctx.client
             |> get_json("#{ctx.me}/signatures/#{signature["id"]}/evidence")
             |> json_response(200)

    assert is_binary(url)

    # Staff see it, and their download is audited.
    assert %{"signatures" => [%{"user_id" => user_id, "user_agent" => "Mozilla/5.0 (Test)"}]} =
             ctx.owner |> get_json("#{ctx.admin}/signatures") |> json_response(200)

    assert user_id == ctx.client_user.id

    assert ctx.owner
           |> get_json("#{ctx.admin}/signatures/#{signature["id"]}/evidence")
           |> json_response(200)

    # Another client cannot download it.
    {_other, other} =
      (fn ->
         user = user_fixture()
         {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user, :member)
         {user, put_bearer_token(build_conn(), user)}
       end).()

    assert other
           |> get_json("#{ctx.me}/signatures/#{signature["id"]}/evidence")
           |> json_response(404)

    assert %{"booking" => _} =
             ctx.client
             |> send_json(:post, "#{ctx.org}/bookings", %{"slot_id" => slot.id})
             |> json_response(201)
  end

  test "health certificates: the client uploads; coaches see status only, staff need the capability",
       ctx do
    assert %{"file_key" => key, "upload_url" => _} =
             ctx.client
             |> send_json(:post, "#{ctx.me}/health-certificate/uploads", %{
               "content_type" => "application/pdf"
             })
             |> json_response(200)

    :ok = MemoryObjectStore.put_object(:documents, key, @pdf, "application/pdf")
    issued = Date.utc_today() |> Date.add(-10) |> Date.to_iso8601()

    assert %{"health_certificate" => %{"id" => id, "expires_on" => _}} =
             ctx.client
             |> send_json(:post, "#{ctx.me}/health-certificate", %{
               "file_key" => key,
               "content_type" => "application/pdf",
               "issued_on" => issued
             })
             |> json_response(201)

    assert %{"health_certificates" => [row], "full_access" => true} =
             ctx.owner |> get_json("#{ctx.admin}/health-certificates") |> json_response(200)

    assert row["status"] == "valid" and row["certificate"]["id"] == id

    assert %{"url" => _} =
             ctx.owner
             |> get_json("#{ctx.admin}/health-certificates/#{id}/file")
             |> json_response(200)

    # Front desk sees certificates by default (product owner, 2026-10-29):
    # dates and the file, but uploads and deletes stay with
    # manage_health_certificates. Coaches read statuses only.
    assert %{"health_certificates" => [desk_row], "full_access" => true} =
             ctx.desk |> get_json("#{ctx.admin}/health-certificates") |> json_response(200)

    assert desk_row["certificate"]["id"] == id

    assert %{"url" => _} =
             ctx.desk
             |> get_json("#{ctx.admin}/health-certificates/#{id}/file")
             |> json_response(200)

    assert %{"health_certificates" => [_]} =
             ctx.desk
             |> get_json("#{ctx.admin}/health-certificates/members/#{ctx.client_user.id}")
             |> json_response(200)

    assert ctx.desk
           |> send_json(:post, "#{ctx.admin}/health-certificates/uploads", %{
             "user_id" => ctx.client_user.id,
             "content_type" => "application/pdf"
           })
           |> json_response(403)

    assert ctx.desk
           |> recycle()
           |> delete("#{ctx.admin}/health-certificates/#{id}")
           |> json_response(403)

    {:ok, _} =
      Palee.Coaching.start_relationship(ctx.context, %{
        coach_user_id: ctx.coach_user.id,
        client_user_id: ctx.client_user.id,
        origin: "assigned"
      })

    assert %{"health_certificates" => [coach_row], "full_access" => false} =
             ctx.coach |> get_json("#{ctx.admin}/health-certificates") |> json_response(200)

    assert coach_row["status"] == "valid" and coach_row["certificate"] == nil

    assert ctx.coach
           |> get_json("#{ctx.admin}/health-certificates/#{id}/file")
           |> json_response(403)

    assert %{"health_certificate" => %{"id" => ^id}} =
             ctx.client
             |> recycle()
             |> delete("#{ctx.me}/health-certificate/#{id}")
             |> json_response(200)
  end
end
