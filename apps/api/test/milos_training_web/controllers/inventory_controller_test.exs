defmodule MilosTrainingWeb.InventoryControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.{Notifications, Organizations, Repo}

  import MilosTraining.TestFixtures

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)
    desk = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(desk, :front_desk)
    coach = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(coach, :coach)
    janitor = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(janitor, :janitor)

    %{
      owner: owner,
      owner_conn: put_bearer_token(conn, owner),
      desk_conn: put_bearer_token(conn, desk),
      coach_conn: put_bearer_token(conn, coach),
      janitor_conn: put_bearer_token(conn, janitor),
      base: "/api/org/#{organization.slug}/staff/inventory"
    }
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  test "front desk logs a broken machine and owners hear about it", ctx do
    assert ctx.coach_conn
           |> send_json(:post, "#{ctx.base}/machines", %{name: "Bike", category: "training"})
           |> json_response(403)

    %{"machine" => %{"id" => id, "status" => "working"}} =
      ctx.desk_conn
      |> send_json(:post, "#{ctx.base}/machines", %{
        name: "Rower",
        category: "training",
        brand: "Concept2",
        service_interval_days: 180
      })
      |> json_response(201)

    assert %{"machine" => %{"status" => "out_of_order"}, "event" => %{"kind" => "out_of_order"}} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.base}/machines/#{id}/events", %{
               kind: "out_of_order",
               body: "Chain snapped"
             })
             |> json_response(201)

    assert Enum.any?(
             Notifications.list_for_user(ctx.owner.id),
             &(&1.type == "inventory_repair_needed")
           )

    assert %{"machine" => %{"status" => "working", "last_serviced_on" => _}} =
             ctx.owner_conn
             |> send_json(:post, "#{ctx.base}/machines/#{id}/events", %{
               kind: "repaired",
               cost_cents: 4500
             })
             |> json_response(201)

    assert %{"events" => [_, _]} =
             ctx.owner_conn
             |> recycle()
             |> get("#{ctx.base}/machines/#{id}/events")
             |> json_response(200)
  end

  test "consumables track stock, alert when low and feed the report", ctx do
    %{"supply" => %{"id" => id, "stock" => %{"status" => "ok"}}} =
      ctx.desk_conn
      |> send_json(:post, "#{ctx.base}/supplies", %{
        name: "Paper towels",
        brand: "Tork",
        shop: "Cash & Carry",
        url: "https://example.com/towels",
        unit: "roll",
        unit_price_cents: 150,
        quantity: 30,
        consumption_speed: "fast"
      })
      |> json_response(201)

    assert %{"supply" => %{"quantity" => 40}} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.base}/supplies/#{id}/movements", %{
               kind: "restock",
               quantity: 10,
               unit_price_cents: 140
             })
             |> json_response(201)

    assert %{"supply" => %{"quantity" => 5, "stock" => %{"status" => "critical"}}} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.base}/supplies/#{id}/movements", %{
               kind: "consume",
               quantity: 35
             })
             |> json_response(201)

    assert Enum.any?(
             Notifications.list_for_user(ctx.owner.id),
             &(&1.type == "inventory_stock_low")
           )

    assert %{"code" => "not_enough_stock"} =
             ctx.desk_conn
             |> send_json(:post, "#{ctx.base}/supplies/#{id}/movements", %{
               kind: "consume",
               quantity: 6
             })
             |> json_response(422)

    assert %{
             "supplies" => [%{"consumed" => 35, "spent_cents" => 1400}],
             "totals" => %{"supplies_cents" => 1400}
           } =
             ctx.owner_conn
             |> recycle()
             |> get("#{ctx.base}/report?months=3")
             |> json_response(200)
  end

  test "the team reports low stock and machine trouble with provenance; managers act", ctx do
    %{"supply" => %{"id" => id}} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.base}/supplies", %{
        name: "Hand soap",
        unit_price_cents: 400,
        quantity: 6,
        shop: "Shop"
      })
      |> json_response(201)

    %{"machine" => %{"id" => machine_id}} =
      ctx.owner_conn
      |> send_json(:post, "#{ctx.base}/machines", %{
        name: "Washer",
        category: "appliance",
        purchase_price_cents: 90_000
      })
      |> json_response(201)

    assert %{"supplies" => [supply]} =
             ctx.janitor_conn |> recycle() |> get("#{ctx.base}/supplies") |> json_response(200)

    refute Map.has_key?(supply, "unit_price_cents")
    refute Map.has_key?(supply, "shop")

    assert %{
             "report" => %{
               "note" => "Last bottle",
               "level" => "running_low",
               "seen_quantity" => 1,
               "nickname" => nickname,
               "reported_at" => _
             }
           } =
             ctx.janitor_conn
             |> send_json(:post, "#{ctx.base}/supplies/#{id}/low-reports", %{
               level: "running_low",
               seen_quantity: 1,
               place: "Men's changing room",
               note: "Last bottle"
             })
             |> json_response(201)

    assert is_binary(nickname)

    assert %{"supply" => %{"open_reports" => [_, _]}} =
             ctx.coach_conn
             |> send_json(:post, "#{ctx.base}/supplies/#{id}/low-reports", %{
               note: "Empty in studio"
             })
             |> json_response(201)

    assert Enum.any?(
             Notifications.list_for_user(ctx.owner.id),
             &(&1.type == "inventory_stock_low")
           )

    # Reporters write notes and flag trouble, but cannot service, repair or change stock.
    assert %{"machine" => machine} =
             ctx.coach_conn
             |> send_json(:post, "#{ctx.base}/machines/#{machine_id}/events", %{
               kind: "issue",
               severity: "safety",
               symptom: "leak",
               usable: false,
               body: "Leaking near the socket"
             })
             |> json_response(201)

    # A safety issue takes it out of use at once.
    assert machine["status"] == "out_of_order"
    refute Map.has_key?(machine, "purchase_price_cents")

    assert ctx.janitor_conn
           |> send_json(:post, "#{ctx.base}/machines/#{machine_id}/events", %{kind: "repaired"})
           |> json_response(403)

    assert ctx.janitor_conn
           |> send_json(:post, "#{ctx.base}/supplies/#{id}/movements", %{
             kind: "consume",
             quantity: 1
           })
           |> json_response(403)

    assert ctx.janitor_conn |> recycle() |> get("#{ctx.base}/report") |> json_response(403)

    # A restock resolves the open reports and records who did it.
    ctx.desk_conn
    |> send_json(:post, "#{ctx.base}/supplies/#{id}/movements", %{kind: "restock", quantity: 6})
    |> json_response(201)

    assert %{"reports" => [%{"resolved_at" => resolved, "resolved_by" => resolver}, _]} =
             ctx.owner_conn
             |> recycle()
             |> get("#{ctx.base}/supplies/#{id}/low-reports")
             |> json_response(200)

    assert resolved && resolver
  end

  test "the daily digest tells managers what needs attention", ctx do
    ctx.owner_conn
    |> send_json(:post, "#{ctx.base}/supplies", %{
      name: "Chalk",
      quantity: 1,
      consumption_speed: "fast"
    })
    |> json_response(201)

    assert :ok = MilosTraining.Workers.InventoryDigestJob.perform(%Oban.Job{})

    assert Enum.any?(Notifications.list_for_user(ctx.owner.id), fn notification ->
             notification.type == "inventory_digest" and
               notification.payload["low_stock"] in [1, "1"]
           end)
  end
end
