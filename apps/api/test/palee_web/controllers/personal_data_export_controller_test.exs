defmodule PaleeWeb.PersonalDataExportControllerTest do
  @moduledoc """
  ADR-267 over HTTP: "Download my data" is requested, built (in tests at
  once, without Oban), listed with a short-lived link and announced by
  email. The file holds the person's own rows across contexts and
  businesses, never another person's rows, never secrets.
  """

  use PaleeWeb.ConnCase, async: false
  use Palee.EmailCase

  import Palee.TestFixtures

  alias Palee.Application.JournalNotes
  alias Palee.Identity.UserContext
  alias Palee.Infrastructure.Security.MemoryRateLimiter
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.{Organizations, Repo}
  alias Palee.TestSupport.MemoryObjectStore

  setup %{conn: conn} do
    MemoryRateLimiter.reset!()
    box = org!("Box Kypseli")
    other_box = org!("Box Pangrati")
    me = user_fixture()
    other = user_fixture()
    add!(box, me)
    add!(other_box, me)
    add!(box, other)

    %{conn: conn, box: box, other_box: other_box, me: me, other: other}
  end

  defp authed(ctx, user \\ nil), do: ctx.conn |> recycle() |> put_bearer_token(user || ctx.me)

  test "a request is built, listed with a link, emailed and holds only my own data", ctx do
    seed!(ctx)

    %{"export" => export} = authed(ctx) |> post("/api/me/data-exports") |> json_response(202)

    assert export["status"] == "ready"
    assert export["record_count"] > 0
    assert %{"name" => name, "download_url" => url, "bytes" => bytes} = export["file"]
    assert name =~ ~r/^palee-my-data-\d{4}-\d{2}-\d{2}\.zip$/
    assert is_binary(url) and bytes > 0

    %{"exports" => [listed]} = authed(ctx) |> get("/api/me/data-exports") |> json_response(200)
    assert listed["id"] == export["id"]
    assert listed["file"]["download_url"]

    notice = assert_email_enqueued(kind: :personal_data_export_ready, to: ctx.me.email)
    assert notice.text =~ "/me/settings#your-data"
    refute notice.text =~ "media.test"

    files = unzip!(ctx.me.id, export["id"], name)
    everything = Jason.encode!(files)

    # My own rows, from both businesses and from my own account.
    assert [%{"body" => "My note"}] = files["training.json"]["journal_notes"]
    assert [%{"body" => "From me"}] = files["messages.json"]["person_messages"]

    assert files["payments.json"]["memberships"]
           |> Enum.map(& &1["organization_id"])
           |> Enum.sort() ==
             Enum.sort([ctx.box.id, ctx.other_box.id])

    assert [%{"invoice_number" => "INV-ME"}] = files["payments.json"]["finance_invoices"]

    assert [%{"package_name_snapshot" => "PKG-ME"} = request] =
             files["payments.json"]["finance_package_requests"]

    refute Map.has_key?(request, "requested_by_id")
    assert [%{"provider" => "garmin"}] = files["devices.json"]["device_connections"]
    assert [%{"id" => my_id}] = files["profile.json"]["users"]
    assert my_id == ctx.me.id

    # Nobody else's rows, no secrets, no conversation partner.
    refute everything =~ "Other note"
    refute everything =~ "From them"
    refute everything =~ "INV-OTHER"
    refute everything =~ "PKG-OTHER"
    refute everything =~ "SECRET-ACCESS-TOKEN"
    refute everything =~ "password_hash"
    refute everything =~ ctx.other.id

    assert files["manifest.json"]["format"] == "palee-personal-data/v1"
  end

  test "one request a day, and only one at a time", ctx do
    authed(ctx) |> post("/api/me/data-exports") |> json_response(202)

    conn = authed(ctx) |> post("/api/me/data-exports")
    body = json_response(conn, 429)
    assert body["code"] == "export_rate_limited"
    assert {:ok, _at, 0} = DateTime.from_iso8601(body["retry_at"])
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) > 23 * 3_600

    {:ok, _pending} =
      Palee.PersonalData.insert_export(%{user_id: ctx.other.id, requested_at: DateTime.utc_now()})

    assert %{"code" => "export_in_progress"} =
             authed(ctx, ctx.other) |> post("/api/me/data-exports") |> json_response(409)
  end

  test "someone else's exports are never listed", ctx do
    authed(ctx) |> post("/api/me/data-exports") |> json_response(202)

    assert %{"exports" => []} =
             authed(ctx, ctx.other) |> get("/api/me/data-exports") |> json_response(200)
  end

  test "needs a signed-in person", ctx do
    assert ctx.conn |> get("/api/me/data-exports") |> json_response(401)
    assert ctx.conn |> recycle() |> post("/api/me/data-exports") |> json_response(401)
  end

  # -- fixtures ------------------------------------------------------------------

  defp seed!(ctx) do
    note!(ctx.me, "My note")
    note!(ctx.other, "Other note")

    my_membership = membership!(ctx.box, ctx.me)
    membership!(ctx.other_box, ctx.me)
    other_membership = membership!(ctx.box, ctx.other)

    invoice!(ctx.box, ctx.me, my_membership, "INV-ME")
    invoice!(ctx.box, ctx.other, other_membership, "INV-OTHER")

    package = package!(ctx.box)
    package_request!(ctx.box, ctx.me, package, "PKG-ME")
    package_request!(ctx.box, ctx.other, package, "PKG-OTHER")

    now = DateTime.utc_now()

    Repo.insert_all("device_connections", [
      %{
        id: dump(Ecto.UUID.generate()),
        user_id: dump(ctx.me.id),
        provider: "garmin",
        access_token: "SECRET-ACCESS-TOKEN",
        inserted_at: now,
        updated_at: now
      }
    ])

    [a, b] = Enum.sort([ctx.me.id, ctx.other.id])
    conversation = Ecto.UUID.generate()

    Repo.insert_all("person_conversations", [
      %{
        id: dump(conversation),
        user_a_id: dump(a),
        user_b_id: dump(b),
        started_by_id: dump(ctx.me.id),
        a_folder: "inbox",
        b_folder: "inbox",
        inserted_at: now,
        updated_at: now
      }
    ])

    for {author, body} <- [{ctx.me, "From me"}, {ctx.other, "From them"}] do
      Repo.insert_all("person_messages", [
        %{
          id: dump(Ecto.UUID.generate()),
          conversation_id: dump(conversation),
          user_a_id: dump(a),
          user_b_id: dump(b),
          author_id: dump(author.id),
          body: body,
          inserted_at: now
        }
      ])
    end
  end

  defp note!(user, body) do
    {:ok, _note} =
      JournalNotes.create(UserContext.new(user), %{"topic" => "mood", "body" => body})
  end

  defp membership!(org, user) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    RepoContext.run(%{organization_id: org.id, user_id: user.id}, fn ->
      Repo.insert_all("memberships", [
        %{
          id: dump(id),
          organization_id: dump(org.id),
          user_id: dump(user.id),
          user_type_snapshot: "member",
          inserted_at: now,
          updated_at: now
        }
      ])
    end)

    dump(id)
  end

  defp invoice!(org, user, membership_id, number) do
    now = DateTime.utc_now()

    RepoContext.run(%{organization_id: org.id, user_id: user.id}, fn ->
      Repo.insert_all("finance_invoices", [
        %{
          id: dump(Ecto.UUID.generate()),
          organization_id: dump(org.id),
          user_id: dump(user.id),
          membership_id: membership_id,
          invoice_number: number,
          inserted_at: now,
          updated_at: now
        }
      ])
    end)
  end

  defp package!(org) do
    id = Ecto.UUID.generate()
    now = DateTime.utc_now()

    RepoContext.run(%{organization_id: org.id}, fn ->
      Repo.insert_all("membership_packages", [
        %{
          id: dump(id),
          organization_id: dump(org.id),
          name: "Unlimited",
          family: "unlimited",
          billing_period: "monthly",
          inserted_at: now,
          updated_at: now
        }
      ])
    end)

    dump(id)
  end

  # ADR-291: a package asked for at the desk; the name snapshot tells them apart.
  defp package_request!(org, user, package_id, name) do
    now = DateTime.utc_now()

    RepoContext.run(%{organization_id: org.id, user_id: user.id}, fn ->
      Repo.insert_all("finance_package_requests", [
        %{
          id: dump(Ecto.UUID.generate()),
          organization_id: dump(org.id),
          user_id: dump(user.id),
          membership_package_id: package_id,
          package_name_snapshot: name,
          price_cents_snapshot: 7_500,
          currency: "EUR",
          requested_by_id: dump(user.id),
          hold_until: Date.add(Date.utc_today(), 14),
          inserted_at: now,
          updated_at: now
        }
      ])
    end)
  end

  defp unzip!(user_id, export_id, name) do
    %{file: %{"key" => key, "name" => ^name}} = Palee.PersonalData.get_export(export_id, user_id)
    assert String.ends_with?(key, "/exports/personal-data/#{export_id}/#{name}")
    assert {:ok, zip} = MemoryObjectStore.get(:media_private, key)
    {:ok, files} = :zip.unzip(zip, [:memory])
    Map.new(files, fn {file, body} -> {to_string(file), Jason.decode!(body)} end)
  end

  defp dump(id), do: Ecto.UUID.dump!(id)

  defp org!(name) do
    {:ok, organization} =
      Organizations.create_organization(%{name: "#{name} #{System.unique_integer([:positive])}"})

    organization
  end

  defp add!(organization, user) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: :member,
        roles: [:member],
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
