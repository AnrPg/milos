defmodule PaleeWeb.AdminImportControllerTest do
  @moduledoc """
  ADR-254 over HTTP: owners upload (multipart), dry-run, apply, read the
  report, invite and undo; members cannot; error codes; the OpenAPI enums
  are the domain's lists.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.Imports.Domain.{DateParser, Encoding, Fields, ImportPolicy, Presets}
  alias Palee.{Organizations, Repo}

  @csv "Name;Email;Amount;Payment date\nMaria P;maria@http.test;45,50;05/01/2027\nNo Email;;;\n"

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner_user = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner_user, :owner)
    member_user = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member_user, :member)

    %{
      owner: put_bearer_token(conn, owner_user),
      member: put_bearer_token(conn, member_user),
      base: "/api/org/#{Organizations.legacy_organization_slug()}/admin/imports"
    }
  end

  defp upload_file(content, name \\ "members.csv") do
    path = Path.join(System.tmp_dir!(), "http-import-#{System.unique_integer([:positive])}.csv")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: name, content_type: "text/csv"}
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp post_multipart(conn, path, params) do
    conn
    |> put_req_header("content-type", "multipart/form-data; boundary=test")
    |> post(path, params)
  end

  defp create_import(conn, base, content \\ @csv) do
    conn
    |> recycle()
    |> post_multipart(base, %{"file" => upload_file(content), "source" => "excel"})
    |> json_response(201)
    |> Map.fetch!("import")
  end

  test "the full flow over HTTP", %{owner: owner, base: base} do
    catalog = owner |> get("#{base}/catalog") |> json_response(200)
    assert Enum.map(catalog["fields"], & &1["key"]) == Fields.keys()
    assert catalog["limits"]["max_rows"] == 20_000

    import = create_import(owner, base)

    assert %{"status" => "draft", "delimiter" => ";", "row_count" => 2, "source" => "excel"} =
             import

    assert Enum.map(import["mapping"], & &1["field"]) ==
             ~w(full_name email payment_amount payment_date)

    preview =
      owner |> send_json("POST", "#{base}/#{import["id"]}/preview", %{}) |> json_response(200)

    assert preview["import"]["preview"]["outcomes"] == %{"create_person" => 2}

    applied =
      owner |> send_json("POST", "#{base}/#{import["id"]}/apply", %{}) |> json_response(202)

    assert applied["import"]["status"] == "applied"
    assert applied["import"]["undo_until"]

    rows =
      owner
      |> recycle()
      |> get("#{base}/#{import["id"]}/rows?status=applied&limit=1")
      |> json_response(200)

    assert [%{"row_number" => 1, "outcome" => "create_person"}] = rows["rows"]
    assert rows["next_after_row"] == 1

    rows =
      owner |> recycle() |> get("#{base}/#{import["id"]}/rows?after_row=1") |> json_response(200)

    assert [%{"row_number" => 2}] = rows["rows"]
    assert rows["next_after_row"] == nil

    sent =
      owner |> send_json("POST", "#{base}/#{import["id"]}/invitations", %{}) |> json_response(200)

    assert %{"sent" => 1, "failed" => 0, "remaining" => 0} = sent

    assert [%{"id" => id}] =
             owner |> recycle() |> get(base) |> json_response(200) |> Map.fetch!("imports")

    assert id == import["id"]

    assert %{"code" => "import_already_applied"} =
             owner |> recycle() |> delete("#{base}/#{id}") |> json_response(409)

    undone = owner |> send_json("POST", "#{base}/#{id}/undo", %{}) |> json_response(200)
    assert undone["import"]["status"] == "undone"

    assert %{"code" => "import_already_undone"} =
             owner |> send_json("POST", "#{base}/#{id}/undo", %{}) |> json_response(409)
  end

  test "error codes", %{owner: owner, base: base} do
    # The schema requires the file part.
    assert %{"errors" => [%{"source" => %{"pointer" => "/file"}}]} =
             owner |> post_multipart(base, %{"source" => "excel"}) |> json_response(422)

    too_large = String.duplicate("a", 5 * 1024 * 1024 + 1)

    assert %{"code" => "file_too_large"} =
             owner
             |> recycle()
             |> post_multipart(base, %{"file" => upload_file(too_large)})
             |> json_response(413)

    assert %{"code" => "no_rows"} =
             owner
             |> recycle()
             |> post_multipart(base, %{"file" => upload_file("Name\n")})
             |> json_response(422)

    assert %{"code" => "unbalanced_quotes"} =
             owner
             |> recycle()
             |> post_multipart(base, %{"file" => upload_file("Name\n\"Open\n")})
             |> json_response(422)

    import = create_import(owner, base)

    assert %{"code" => "invalid_mapping"} =
             owner
             |> send_json("POST", "#{base}/#{import["id"]}/preview", %{
               "mapping" => [%{"column" => 0, "field" => "notes"}]
             })
             |> json_response(422)

    # An unknown field is refused by the schema itself.
    assert owner
           |> send_json("POST", "#{base}/#{import["id"]}/preview", %{
             "mapping" => [%{"column" => 0, "field" => "age"}]
           })
           |> json_response(422)

    assert %{"code" => "import_not_applied"} =
             owner |> send_json("POST", "#{base}/#{import["id"]}/undo", %{}) |> json_response(409)

    assert owner |> recycle() |> delete("#{base}/#{import["id"]}") |> response(204)
    assert owner |> recycle() |> get("#{base}/#{import["id"]}") |> json_response(404)
  end

  test "members cannot import", %{member: member, owner: owner, base: base} do
    import = create_import(owner, base)

    assert member |> recycle() |> get(base) |> json_response(403)

    assert member
           |> recycle()
           |> post_multipart(base, %{"file" => upload_file(@csv)})
           |> json_response(403)

    assert member |> send_json("POST", "#{base}/#{import["id"]}/apply", %{}) |> json_response(403)
  end

  test "the OpenAPI enums are the domain's lists" do
    spec = PaleeWeb.ApiSpec.spec() |> Jason.encode!() |> Jason.decode!()

    path = fn suffix ->
      Enum.find_value(spec["paths"], fn {path, item} ->
        String.ends_with?(path, "/admin/imports" <> suffix) && item
      end) || flunk("no path ending in #{suffix}")
    end

    params = Map.new(path.("/{id}/rows")["get"]["parameters"], &{&1["name"], &1["schema"]})
    assert params["status"]["enum"] == ImportPolicy.row_statuses()
    assert params["outcome"]["enum"] == ImportPolicy.outcomes()

    import =
      path.("/{id}")["get"]["responses"]["200"]["content"]["application/json"]["schema"][
        "properties"
      ][
        "import"
      ]["properties"]

    assert import["status"]["enum"] == ImportPolicy.statuses()
    assert import["source"]["enum"] == Presets.keys()
    assert import["date_order"]["enum"] == DateParser.orders()
    assert import["default_role"]["enum"] == ImportPolicy.roles()
    assert import["encoding"]["enum"] == Encoding.encodings()
    assert import["mapping"]["items"]["properties"]["field"]["enum"] == Fields.keys()

    upload = path.("")["post"]["requestBody"]["content"]["multipart/form-data"]["schema"]
    assert upload["properties"]["source"]["enum"] == Presets.keys()
    assert upload["properties"]["file"]["format"] == "binary"
  end
end
