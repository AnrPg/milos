defmodule MilosTrainingWeb.WalletCheckInTest do
  @moduledoc """
  ADR-155 (P2-M7): Wallet cards for boxes with static personal codes - add,
  download, scan at the desk, revoke (which resets the code), the PassKit web
  service, updates on book/cancel, platform pushes behind the updater port,
  Google save links, «not configured», and Εγώ › Συνδεδεμένες συσκευές.
  """

  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.{SubmitBooking, WalletPasses, WithdrawBooking}
  alias MilosTraining.{Facility, FakeWalletUpdater, Organizations, Repo, Wallet}

  @pass_type "pass.test.milos"

  setup do
    previous = Application.get_env(:milos_training, :wallet)

    on_exit(fn ->
      FakeWalletUpdater.unsubscribe()

      if previous,
        do: Application.put_env(:milos_training, :wallet, previous),
        else: Application.delete_env(:milos_training, :wallet)
    end)

    %{cert: cert, key: key} =
      :public_key.pkix_test_root_cert(~c"Milos Wallet Test", [{:key, {:rsa, 2048, 17}}])

    cert_pem = :public_key.pem_encode([{:Certificate, cert, :not_encrypted}])
    key_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

    Application.put_env(:milos_training, :wallet,
      apple: [
        pass_type_identifier: @pass_type,
        team_identifier: "TEAM123456",
        certificate: cert_pem,
        private_key: key_pem,
        wwdr_certificate: cert_pem
      ],
      google: [
        issuer_id: "3388000000012345678",
        service_account_email: "wallet@project.iam.gserviceaccount.com",
        private_key: key_pem,
        origins: ["https://app.example.test"]
      ]
    )

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "Wallet Box #{System.unique_integer([:positive])}"
      })

    owner = user_fixture()
    add_member(organization, owner, :owner)
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)
    {:ok, location} = Facility.create_location(context, %{name: "Κεντρικό"})
    {:ok, _rules} = Facility.update_check_in_rules(context, %{member_code_mode: "static"})
    _class_type = class_type_fixture(%{tenant_context: context})
    workout = workout_fixture(owner, %{tenant_context: context, title: "Wallet WOD"})
    member = add_member(organization, user_fixture())
    {:ok, member_context} = Organizations.resolve_tenant_context(member, organization.slug)

    %{
      organization: organization,
      owner: owner,
      context: context,
      location: location,
      workout: workout,
      member: member,
      member_context: member_context,
      me: "/api/org/#{organization.slug}/me",
      admin: "/api/org/#{organization.slug}/admin/check-in"
    }
  end

  defp add_member(organization, user, role \\ :member) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    user
  end

  defp add_pass(ctx, platform) do
    build_conn()
    |> put_bearer_token(ctx.member)
    |> post("#{ctx.me}/wallet-passes", %{platform: platform})
  end

  defp download(url) do
    build_conn() |> get(URI.parse(url).path)
  end

  defp unzip(body) do
    {:ok, entries} = :zip.unzip(body, [:memory])
    Map.new(entries, fn {name, bytes} -> {to_string(name), bytes} end)
  end

  defp apple_pass(ctx) do
    %{"pass" => pass, "download_url" => url} = add_pass(ctx, "apple") |> json_response(200)
    conn = download(url)
    assert response(conn, 200)
    files = unzip(conn.resp_body)
    %{pass: pass, url: url, json: Jason.decode!(files["pass.json"]), files: files}
  end

  defp desk(ctx, code) do
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> post("#{ctx.admin}/scan-member", %{code: code, location_id: ctx.location.id})
  end

  defp passkit(conn, serial, token),
    do:
      put_req_header(
        conn,
        "authorization",
        "ApplePass " <> (token || WalletPasses.auth_token(serial))
      )

  defp registration_path(device, serial),
    do: "/api/wallet/apple/v1/devices/#{device}/registrations/#{@pass_type}/#{serial}"

  defp slot(ctx, minutes) do
    slot_fixture(ctx.workout, %{
      tenant_context: ctx.context,
      auto_approve: true,
      location_id: ctx.location.id,
      scheduled_at: DateTime.utc_now() |> DateTime.add(minutes * 60) |> DateTime.truncate(:second)
    })
  end

  defp pass_row(ctx, id), do: Wallet.get_pass(%{organization_id: ctx.organization.id}, id)

  test "Apple: a signed .pkpass carrying the static code, which scans at the desk as wallet",
       ctx do
    %{pass: pass, json: json, files: files, url: url} = apple_pass(ctx)

    assert pass["platform"] == "apple"
    assert pass["active"] == true

    assert Map.keys(files) |> Enum.sort() ==
             ~w(icon.png icon@2x.png logo.png manifest.json pass.json signature)

    assert json["passTypeIdentifier"] == @pass_type
    assert json["webServiceURL"] =~ "/api/wallet/apple"
    assert json["authenticationToken"] == WalletPasses.auth_token(json["serialNumber"])
    assert [%{"message" => "W1" <> _ = barcode}] = json["barcodes"]

    # The barcode is the member's static code, in its Wallet form.
    app_code =
      build_conn()
      |> put_bearer_token(ctx.member)
      |> get("#{ctx.me}/check-in/code")
      |> json_response(200)

    refute app_code["code"] == barcode

    assert %{"method" => "wallet", "member" => %{"id" => id}} =
             desk(ctx, barcode) |> json_response(200)

    assert id == ctx.member.id

    # Adding again returns the same card.
    assert %{"pass" => %{"id" => same}} = add_pass(ctx, "apple") |> json_response(200)
    assert same == pass["id"]

    # The download link is personal and short-lived, not a bearer of anything else.
    assert %{"code" => "invalid_download_link"} =
             build_conn() |> get("/api/wallet/passes/forged") |> json_response(422)

    assert response(download(url), 200)
  end

  test "revoking a card stops its barcode and resets the code", ctx do
    %{pass: pass, json: json, url: url} = apple_pass(ctx)
    [%{"message" => barcode}] = json["barcodes"]
    %{"pass" => google} = add_pass(ctx, "google") |> json_response(200)

    assert %{"pass" => %{"active" => false, "revoked_at" => revoked_at}} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> delete("/api/me/wallet-passes/#{pass["id"]}")
             |> json_response(200)

    assert revoked_at
    assert %{"code" => "member_code_revoked"} = desk(ctx, barcode) |> json_response(422)
    assert %{"code" => "pass_revoked"} = download(url) |> json_response(422)

    # Both cards carried the code, so both are void.
    refute is_nil(pass_row(ctx, google["id"]).revoked_at)

    # Someone else cannot revoke my card.
    build_conn()
    |> put_bearer_token(ctx.owner)
    |> delete("/api/me/wallet-passes/#{pass["id"]}")
    |> json_response(404)

    # A new card carries the new code.
    %{json: again} = apple_pass(ctx)
    refute again["serialNumber"] == json["serialNumber"]
    [%{"message" => new_barcode}] = again["barcodes"]
    assert %{"method" => "wallet"} = desk(ctx, new_barcode) |> json_response(200)
  end

  test "staff revoke and going back to rotating codes void the cards", ctx do
    %{pass: pass, json: json} = apple_pass(ctx)
    [%{"message" => barcode}] = json["barcodes"]

    build_conn()
    |> put_bearer_token(ctx.owner)
    |> delete("#{ctx.admin}/members/#{ctx.member.id}/code")
    |> json_response(200)

    refute is_nil(pass_row(ctx, pass["id"]).revoked_at)
    assert %{"code" => "member_code_revoked"} = desk(ctx, barcode) |> json_response(422)

    %{pass: second} = apple_pass(ctx)

    build_conn()
    |> put_bearer_token(ctx.owner)
    |> put("#{ctx.admin}/settings", %{member_code_mode: "rotating"})
    |> json_response(200)

    refute is_nil(pass_row(ctx, second["id"]).revoked_at)

    assert %{"code" => "wallet_requires_static_code"} =
             add_pass(ctx, "apple") |> json_response(409)
  end

  test "PassKit web service: register, changed serials, latest pass, log, unregister", ctx do
    %{json: json} = apple_pass(ctx)
    serial = json["serialNumber"]
    device = "device-#{System.unique_integer([:positive])}"
    path = registration_path(device, serial)

    build_conn()
    |> passkit(serial, "wrong")
    |> post(path, %{pushToken: "push-1"})
    |> response(401)

    build_conn() |> post(path, %{pushToken: "push-1"}) |> response(401)
    build_conn() |> passkit(serial, nil) |> post(path, %{}) |> response(400)

    assert build_conn()
           |> passkit(serial, nil)
           |> post(path, %{pushToken: "push-1"})
           |> response(201)

    assert build_conn()
           |> passkit(serial, nil)
           |> post(path, %{pushToken: "push-1"})
           |> response(200)

    serials_path = "/api/wallet/apple/v1/devices/#{device}/registrations/#{@pass_type}"

    assert %{"serialNumbers" => [^serial], "lastUpdated" => tag} =
             build_conn() |> get(serials_path) |> json_response(200)

    assert build_conn() |> get(serials_path <> "?passesUpdatedSince=#{tag}") |> response(204)

    # A booking changes the next-booking line: the card is marked updated.
    Process.sleep(5)
    {:ok, booking} = SubmitBooking.call(ctx.member_context, ctx.member, slot(ctx, 120).id)

    assert %{"serialNumbers" => [^serial], "lastUpdated" => newer} =
             build_conn()
             |> get(serials_path <> "?passesUpdatedSince=#{tag}")
             |> json_response(200)

    assert String.to_integer(newer) > String.to_integer(tag)

    latest_path = "/api/wallet/apple/v1/passes/#{@pass_type}/#{serial}"
    conn = build_conn() |> passkit(serial, nil) |> get(latest_path)
    assert response(conn, 200)
    assert [last_modified] = get_resp_header(conn, "last-modified")
    updated = conn.resp_body |> unzip() |> Map.fetch!("pass.json") |> Jason.decode!()

    assert [%{"key" => "next"}, %{"key" => "class", "value" => class_line}] =
             updated["generic"]["secondaryFields"]

    assert class_line =~ "Κεντρικό"

    assert build_conn()
           |> passkit(serial, nil)
           |> put_req_header("if-modified-since", last_modified)
           |> get(latest_path)
           |> response(304)

    build_conn() |> passkit(serial, "wrong") |> get(latest_path) |> response(401)

    build_conn()
    |> passkit(serial, nil)
    |> get("/api/wallet/apple/v1/passes/pass.other/#{serial}")
    |> response(401)

    # Cancelling marks it updated again.
    Process.sleep(5)
    {:ok, _cancelled} = WithdrawBooking.call(ctx.member_context, ctx.member.id, booking.id)

    assert %{"lastUpdated" => after_cancel} =
             build_conn()
             |> get(serials_path <> "?passesUpdatedSince=#{newer}")
             |> json_response(200)

    assert String.to_integer(after_cancel) > String.to_integer(newer)

    assert build_conn() |> post("/api/wallet/apple/v1/log", %{logs: ["hello"]}) |> response(200)
    assert build_conn() |> passkit(serial, nil) |> delete(path) |> response(200)
    assert build_conn() |> get(serials_path) |> response(204)
  end

  test "platform updates go through the updater port; gone push tokens are forgotten", ctx do
    FakeWalletUpdater.subscribe()
    %{pass: pass, json: json} = apple_pass(ctx)
    serial = json["serialNumber"]

    for {device, token} <- [{"dev-a", "push-a"}, {"dev-b", "gone-b"}] do
      build_conn()
      |> passkit(serial, nil)
      |> post(registration_path(device, serial), %{pushToken: token})
      |> response(201)
    end

    assert :ok = WalletPasses.push(ctx.organization.id, pass["id"])
    assert_receive {:wallet_update, %{push_tokens: tokens}}
    assert Enum.sort(tokens) == ["gone-b", "push-a"]
    assert Wallet.push_tokens(%{organization_id: ctx.organization.id}, pass["id"]) == ["push-a"]

    %{"pass" => google} = add_pass(ctx, "google") |> json_response(200)
    assert :ok = WalletPasses.push(ctx.organization.id, google["id"])
    assert_receive {:wallet_update, %{content: content}}
    assert "W1" <> _ = content.barcode
  end

  test "Google: a save link with a signed JWT", ctx do
    assert %{
             "pass" => %{"platform" => "google"},
             "save_url" => "https://pay.google.com/gp/v/save/" <> jwt,
             "download_url" => nil
           } =
             add_pass(ctx, "google") |> json_response(200)

    assert [_header, payload, _signature] = String.split(jwt, ".")
    claims = payload |> Base.url_decode64!(padding: false) |> Jason.decode!()
    assert claims["typ"] == "savetowallet"
    assert [%{"barcode" => %{"value" => "W1" <> _}}] = claims["payload"]["genericObjects"]
  end

  test "without credentials Wallet answers wallet_not_configured; check-in still works", ctx do
    Application.put_env(:milos_training, :wallet, apple: [], google: [])

    assert %{"code" => "wallet_not_configured"} = add_pass(ctx, "apple") |> json_response(503)
    assert %{"code" => "wallet_not_configured"} = add_pass(ctx, "google") |> json_response(503)
    assert %{"errors" => _} = add_pass(ctx, "nokia") |> json_response(422)

    assert %{"mode" => "static", "code" => code} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> get("#{ctx.me}/check-in/code")
             |> json_response(200)

    assert %{"method" => "member_qr"} = desk(ctx, code) |> json_response(200)

    assert %{"wallet" => %{"platforms" => %{"apple" => false, "google" => false}}} =
             build_conn()
             |> put_bearer_token(ctx.member)
             |> get("/api/me/connected-devices")
             |> json_response(200)
  end

  test "connected devices: cards at every box, the calendar feed, honest integrations", ctx do
    %{pass: pass} = apple_pass(ctx)

    devices =
      build_conn()
      |> put_bearer_token(ctx.member)
      |> get("/api/me/connected-devices")
      |> json_response(200)

    assert %{"platforms" => %{"apple" => true, "google" => true}, "passes" => [listed]} =
             devices["wallet"]

    assert listed["id"] == pass["id"]
    assert listed["box"]["slug"] == ctx.organization.slug
    assert devices["calendar"]["https_url"] =~ "http"
    assert devices["calendar"]["webcal_url"] =~ "webcal"

    # ADR-161: without Garmin credentials the row stays «Σύντομα».
    assert [
             %{"provider" => "garmin", "status" => "unavailable", "configured" => false},
             %{"provider" => "apple_health", "status" => "native_only"},
             %{"provider" => "health_connect", "status" => "native_only"}
           ] = devices["integrations"]

    # ADR-172: the phone rows wait for the store app, with every kind on.
    for row <- Enum.drop(devices["integrations"], 1) do
      assert %{"status" => "native_only", "connection" => nil, "history_days" => 30} = row
      assert Enum.all?(Map.values(row["sync_prefs"]))
      assert map_size(row["sync_prefs"]) == 5
    end

    # Nobody else sees my cards.
    assert %{"wallet" => %{"passes" => []}} =
             build_conn()
             |> put_bearer_token(ctx.owner)
             |> get("/api/me/connected-devices")
             |> json_response(200)
  end

  test "pass rows never leak their auth token", ctx do
    %{pass: pass} = apple_pass(ctx)
    refute Map.has_key?(pass, "auth_token_hash")

    [[hash]] =
      Repo.query!("SELECT auth_token_hash FROM wallet_passes WHERE id = $1", [
        Ecto.UUID.dump!(pass["id"])
      ]).rows

    serial = pass_row(ctx, pass["id"]).serial
    assert hash == :crypto.hash(:sha256, WalletPasses.auth_token(serial))
  end
end
