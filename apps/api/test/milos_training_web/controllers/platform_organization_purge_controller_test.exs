defmodule MilosTrainingWeb.PlatformOrganizationPurgeControllerTest do
  use MilosTrainingWeb.ConnCase, async: false
  use Oban.Testing, repo: MilosTraining.Repo

  import MilosTraining.TenantPurgeFixtures
  import MilosTraining.TestFixtures

  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.Organization
  alias MilosTraining.Repo
  alias MilosTraining.Workers.{ExecuteOrganizationPurgeJob, ExportOrganizationTenantDataJob}

  setup %{conn: conn} do
    start_supervised!(
      {Oban, Keyword.put(Application.fetch_env!(:milos_training, Oban), :testing, :manual)}
    )

    vendor = user_fixture()
    {:ok, _} = Organizations.grant_vendor(vendor.id)
    tenant = seed_tenant("Api Purge Gym")

    %{conn: put_bearer_token(conn, vendor), vendor: vendor, tenant: tenant}
  end

  test "non-vendors cannot reach the purge workflow", %{tenant: tenant} do
    conn =
      build_conn()
      |> put_bearer_token(tenant.owner)
      |> post("/api/platform/organizations/#{tenant.organization.id}/purge")

    assert %{"code" => "vendor_required"} = json_response(conn, 403)
  end

  test "request -> export -> review -> approve -> purge -> status", ctx do
    org_id = ctx.tenant.organization.id
    path = "/api/platform/organizations/#{org_id}/purge"

    assert %{"code" => "not_found"} = ctx.conn |> get(path) |> json_response(404)

    assert %{"purge" => %{"status" => "requested", "id" => purge_id}} =
             ctx.conn |> post(path) |> json_response(201)

    assert %{"code" => "organization_purge_exists"} =
             ctx.conn |> post(path) |> json_response(409)

    assert %{"code" => "organization_purge_in_progress"} =
             ctx.conn
             |> patch("/api/platform/organizations/#{org_id}/lifecycle", %{status: "active"})
             |> json_response(409)

    assert :ok =
             perform_job(ExportOrganizationTenantDataJob, %{
               "purge_id" => purge_id,
               "actor_user_id" => ctx.vendor.id
             })

    status = ctx.conn |> get(path) |> json_response(200)
    assert status["purge"]["status"] == "exported"
    assert status["export_download_url"] =~ "tenant-export.zip"

    contexts = Enum.map(status["purge"]["retention_review"], & &1["context"])
    assert "finance" in contexts and "workouts" in contexts and "storage" in contexts

    assert %{"code" => "purge_confirmation_mismatch"} =
             ctx.conn
             |> post(path <> "/approve", %{confirmation: "wrong"})
             |> json_response(422)

    assert %{"purge" => %{"status" => "approved", "approval_mode" => "typed_confirmation"}} =
             ctx.conn
             |> post(path <> "/approve", %{confirmation: ctx.tenant.organization.slug})
             |> json_response(200)

    assert_enqueued(worker: ExecuteOrganizationPurgeJob, args: %{"purge_id" => purge_id})

    assert %{"code" => "invalid_purge_transition"} =
             ctx.conn |> post(path <> "/cancel") |> json_response(409)

    assert :ok =
             perform_job(ExecuteOrganizationPurgeJob, %{
               "purge_id" => purge_id,
               "actor_user_id" => ctx.vendor.id
             })

    refute Repo.get(Organization, org_id)

    completed = ctx.conn |> get(path) |> json_response(200)
    assert completed["purge"]["status"] == "completed"
    assert completed["export_download_url"] == nil
    assert completed["purge"]["steps"]["finance"]["deleted"]["finance_invoices"] == 1

    assert %{"purges" => [%{"id" => ^purge_id, "status" => "completed"} | _]} =
             ctx.conn |> get("/api/platform/organization-purges") |> json_response(200)

    listed = ctx.conn |> get("/api/platform/organizations") |> json_response(200)
    refute Enum.any?(listed["organizations"], &(&1["organization"]["id"] == org_id))
  end

  test "cancel and resume", ctx do
    org_id = ctx.tenant.organization.id
    path = "/api/platform/organizations/#{org_id}/purge"

    ctx.conn |> post(path) |> json_response(201)

    assert %{"purge" => %{"status" => "requested"}} =
             ctx.conn |> post(path <> "/resume") |> json_response(200)

    assert %{"purge" => %{"status" => "cancelled"}} =
             ctx.conn |> post(path <> "/cancel") |> json_response(200)

    assert %{"code" => "invalid_purge_transition"} =
             ctx.conn |> post(path <> "/resume") |> json_response(409)

    assert %{"organization" => %{"status" => "active"}} =
             ctx.conn
             |> patch("/api/platform/organizations/#{org_id}/lifecycle", %{status: "active"})
             |> json_response(200)
  end
end
