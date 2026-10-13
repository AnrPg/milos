defmodule MilosTrainingWeb.PaymentModelsControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias MilosTraining.{Finance, Organizations, Repo}

  import MilosTraining.TestFixtures
  import Swoosh.TestAssertions

  alias MilosTraining.Application.CorporateInvoicing
  alias MilosTraining.Organizations.OrganizationStore

  setup %{conn: conn} do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    admin = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    {:ok, _settings} =
      Finance.update_finance_settings(%{
        entitlement_enforcement_mode: "enforce_managed",
        entitlement_timezone: "Europe/Athens",
        payment_reminder_interval_days: 7
      })

    %{
      admin_conn: put_bearer_token(conn, admin),
      base: "/api/org/#{Organizations.legacy_organization_slug()}"
    }
  end

  defp member(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(user)

    {:ok, membership} =
      Finance.upsert_membership(user.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "direct"
      })

    {user, membership}
  end

  defp package(type, fields, extra \\ %{}) do
    {:ok, package} =
      Finance.create_package(
        Map.merge(
          %{
            name: "#{type} #{System.unique_integer([:positive])}",
            package_type: type,
            fields: fields
          },
          extra
        )
      )

    package
  end

  defp send_json(conn, method, path, body) do
    conn
    |> recycle()
    |> put_req_header("content-type", "application/json")
    |> dispatch(@endpoint, method, path, Jason.encode!(body))
  end

  defp visit(user, key) do
    Finance.reserve_entitlement(user.id, %{
      channel: :in_person,
      capability: :book_classes,
      allowance: :class_visits,
      quantity: 1,
      source_context: "scheduling",
      source_id: Ecto.UUID.generate(),
      occurred_on: Date.utc_today(),
      idempotency_key: key
    })
  end

  defp capabilities(user) do
    case Finance.get_effective_entitlement(user.id).plan do
      %{capabilities: capabilities} -> capabilities
      nil -> []
    end
  end

  test "add-ons attach to a compatible membership and add their benefits" do
    {user, membership} = member()
    {_lonely, lonely_membership} = member()
    base = package("membership", %{})
    other = package("membership", %{})
    add_on = package("add_on", %{})
    picky = package("add_on", %{"terms.compatible_package_ids" => [other.id]})

    assert {:error, :add_on_base_required} =
             Finance.assign_package(lonely_membership.id, add_on.id, %{})

    {:ok, base_subscription} = Finance.assign_package(membership.id, base.id, %{})
    refute :receive_nutrition_plan in capabilities(user)

    {:ok, add_on_subscription} = Finance.assign_package(membership.id, add_on.id, %{})
    assert add_on_subscription.base_subscription_id == base_subscription.id
    assert add_on_subscription.ends_on == nil
    assert :receive_nutrition_plan in capabilities(user)
    assert :book_classes in capabilities(user)

    assert {:error, :add_on_base_required} = Finance.assign_package(membership.id, picky.id, %{})

    # Ending the base ends the add-on: its benefits go and it is not renewed.
    Repo.update_all(
      from(subscription in MilosTraining.Finance.MembershipPackageSubscription,
        where: subscription.id == ^base_subscription.id
      ),
      set: [status: "cancelled"]
    )

    refute :receive_nutrition_plan in capabilities(user)

    assert {:error, :add_on_base_ended} =
             Finance.generate_renewal_invoice(membership.id, %{
               "membership_package_subscription_id" => add_on_subscription.id
             })
  end

  test "shared memberships give beneficiaries per-person or pooled quotas", %{
    admin_conn: admin_conn,
    base: base
  } do
    {payer, payer_membership} = member()
    {partner, _} = member()
    {third, _} = member()

    per_person =
      package("shared", %{"group_classes.visits" => %{"limit" => 1, "period" => "calendar_month"}})

    {:ok, subscription} = Finance.assign_package(payer_membership.id, per_person.id, %{})
    path = "#{base}/admin/finance/subscriptions/#{subscription.id}/beneficiaries"

    assert %{"code" => "minor_beneficiaries_not_allowed"} =
             admin_conn
             |> send_json(:post, path, %{user_id: partner.id, is_minor: true})
             |> json_response(422)

    beneficiary =
      admin_conn
      |> send_json(:post, path, %{user_id: partner.id})
      |> json_response(201)
      |> Map.fetch!("beneficiary")

    assert %{"code" => "beneficiary_limit_reached"} =
             admin_conn |> send_json(:post, path, %{user_id: third.id}) |> json_response(409)

    assert %{"code" => "beneficiary_is_payer"} =
             admin_conn |> send_json(:post, path, %{user_id: payer.id}) |> json_response(422)

    assert {:ok, _} = visit(partner, "shared-partner-1")
    assert {:ok, _} = visit(payer, "shared-payer-1")
    assert {:error, :finance_allowance_exhausted, _} = visit(partner, "shared-partner-2")

    assert [%{"user_id" => partner_id}] =
             admin_conn
             |> recycle()
             |> get(path)
             |> json_response(200)
             |> Map.fetch!("beneficiaries")

    assert partner_id == partner.id

    admin_conn
    |> send_json(:post, "#{path}/#{beneficiary["id"]}/remove", %{})
    |> json_response(200)

    assert Finance.get_effective_entitlement(partner.id).plan == nil

    {pooled_payer, pooled_membership} = member()
    {pooled_partner, _} = member()

    pooled =
      package("shared", %{
        "group_classes.visits" => %{"limit" => 1, "period" => "calendar_month"},
        "terms.quota_sharing" => "shared"
      })

    {:ok, pooled_subscription} = Finance.assign_package(pooled_membership.id, pooled.id, %{})

    admin_conn
    |> send_json(
      :post,
      "#{base}/admin/finance/subscriptions/#{pooled_subscription.id}/beneficiaries",
      %{
        user_id: pooled_partner.id
      }
    )
    |> json_response(201)

    assert {:ok, _} = visit(pooled_partner, "pooled-partner-1")
    assert {:error, :finance_allowance_exhausted, _} = visit(pooled_payer, "pooled-payer-1")
  end

  test "corporate clients enroll employees on seats the company pays for", %{
    conn: conn,
    admin_conn: admin_conn,
    base: base
  } do
    corporate =
      package(
        "corporate",
        %{
          "terms.seats" => 2,
          "terms.seat_billing" => "used",
          "terms.enrollment" => "email_domain",
          "terms.enrollment_domain" => "acme.test"
        },
        %{base_price_cents: 3000}
      )

    {_direct, direct_membership} = member()

    assert {:error, :corporate_package_requires_enrollment} =
             Finance.assign_package(direct_membership.id, corporate.id, %{})

    client =
      admin_conn
      |> send_json(:post, "#{base}/admin/finance/corporate-clients", %{
        membership_package_id: corporate.id,
        company_name: "Acme",
        billing_email: "billing@acme.test"
      })
      |> json_response(201)
      |> Map.fetch!("client")

    assert client["seats"] == 2
    assert client["enrollment"] == "email_domain"

    {employee, employee_membership} =
      member(%{email: "jo#{System.unique_integer([:positive])}@acme.test"})

    {outsider, _} = member()

    offer = fn user ->
      conn
      |> put_bearer_token(user)
      |> get("#{base}/me/corporate-enrollment")
      |> json_response(200)
      |> Map.fetch!("offer")
    end

    assert offer.(employee) == %{"company_name" => "Acme"}
    assert offer.(outsider) == nil

    seat =
      conn
      |> put_bearer_token(employee)
      |> send_json(:post, "#{base}/me/corporate-enrollment", %{})
      |> json_response(201)
      |> Map.fetch!("seat")

    assert :book_classes in capabilities(employee)
    assert offer.(employee) == nil

    assert %{"code" => "corporate_enrollment_not_found"} =
             conn
             |> put_bearer_token(outsider)
             |> send_json(:post, "#{base}/me/corporate-enrollment", %{})
             |> json_response(404)

    conn
    |> put_bearer_token(outsider)
    |> send_json(:post, "#{base}/me/corporate-enrollment", %{
      code: String.downcase(client["enrollment_code"])
    })
    |> json_response(201)

    {late, _} = member()

    assert %{"code" => "corporate_seats_full"} =
             admin_conn
             |> send_json(
               :post,
               "#{base}/admin/finance/corporate-clients/#{client["id"]}/seats",
               %{user_id: late.id}
             )
             |> json_response(409)

    assert {:error, :corporate_seat_billed_to_company} =
             Finance.generate_renewal_invoice(employee_membership.id, %{
               membership_package_subscription_id: seat["id"]
             })

    invoice =
      admin_conn
      |> send_json(:post, "#{base}/admin/finance/corporate-clients/#{client["id"]}/invoices", %{})
      |> json_response(201)
      |> Map.fetch!("invoice")

    assert %{"seats_billed" => 2, "total_cents" => 6000, "status" => "issued"} = invoice

    assert admin_conn
           |> send_json(
             :post,
             "#{base}/admin/finance/corporate-clients/#{client["id"]}/invoices",
             %{}
           )
           |> json_response(422)

    assert invoice["invoice_number"] =~ ~r/^INV-\d{6}-CORP-/
    assert invoice["due_on"] == Date.to_iso8601(Date.add(Date.utc_today(), 14))
    invoice_path = "#{base}/admin/finance/corporate-invoices/#{invoice["id"]}"

    pay = fn amount ->
      send_json(admin_conn, :post, "#{invoice_path}/payments", %{
        amount_cents: amount,
        payment_method: "bank_transfer",
        reference: "ACME-#{amount}"
      })
    end

    assert %{"invoice" => %{"status" => "issued", "balance_cents" => 4000}} =
             pay.(2000) |> json_response(201)

    assert %{"code" => "payment_exceeds_balance"} = pay.(4001) |> json_response(422)

    assert %{"code" => "corporate_invoice_has_payments"} =
             admin_conn
             |> send_json(:post, "#{invoice_path}/status", %{status: "void"})
             |> json_response(409)

    paid = pay.(4000) |> json_response(201) |> Map.fetch!("invoice")
    assert %{"status" => "paid", "balance_cents" => 0, "paid_cents" => 6000} = paid

    [first | _] = paid["payments"]

    assert %{"invoice" => %{"status" => "issued", "balance_cents" => 2000}} =
             admin_conn
             |> send_json(:post, "#{invoice_path}/payments/#{first["id"]}/reverse", %{
               reason: "Bounced"
             })
             |> json_response(200)

    document = admin_conn |> recycle() |> get(invoice_path) |> json_response(200)

    assert %{"client" => %{"company_name" => "Acme"}, "issuer" => %{"name" => _}} =
             document["invoice"]

    assert %{"invoice" => %{"status" => "issued"}} =
             admin_conn |> send_json(:post, "#{invoice_path}/send", %{}) |> json_response(200)

    assert_email_sent(to: [{"", "billing@acme.test"}])

    admin_conn
    |> send_json(
      :post,
      "#{base}/admin/finance/corporate-clients/#{client["id"]}/seats/#{seat["id"]}/end",
      %{}
    )
    |> json_response(200)

    seats =
      admin_conn
      |> recycle()
      |> get("#{base}/admin/finance/corporate-clients/#{client["id"]}/seats")
      |> json_response(200)

    assert Enum.count(seats["seats"], &(&1["status"] == "active")) == 1
    assert Enum.any?(seats["seats"], &(&1["nickname"] == employee.nickname))
  end

  test "the daily run issues, marks overdue and reminds once per interval" do
    corporate =
      package(
        "corporate",
        %{"terms.seats" => 3, "terms.seat_billing" => "agreed"},
        %{base_price_cents: 2000}
      )

    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    context = %{organization_id: organization.id}

    {:ok, client} =
      Finance.create_corporate_client(context, %{
        membership_package_id: corporate.id,
        company_name: "Initech",
        billing_email: "ap@initech.test",
        payment_terms_days: 10
      })

    tenant = %{
      organization: organization,
      settings: OrganizationStore.get_organization_settings(organization.id)
    }

    # A day early in next month's period, so the period starts after the client.
    issue_day =
      Date.utc_today() |> Date.beginning_of_month() |> Date.shift(month: 1) |> Date.add(2)

    assert %{issued: 1, reminded: 0} = CorporateInvoicing.run(tenant, issue_day)
    assert_email_sent(fn email -> String.starts_with?(email.subject, "Invoice ") end)

    assert [%{total_cents: 6000, status: "issued", due_on: due_on}] =
             Finance.list_corporate_invoices(context, client.id)

    assert due_on == Date.add(issue_day, 10)
    assert %{issued: 0} = CorporateInvoicing.run(tenant, issue_day)

    late = Date.add(due_on, 1)
    assert %{overdue: 1, reminded: 1} = CorporateInvoicing.run(tenant, late)
    assert_email_sent(fn email -> String.starts_with?(email.subject, "Reminder: invoice ") end)
    assert %{reminded: 0} = CorporateInvoicing.run(tenant, Date.add(late, 3))
    assert %{reminded: 1} = CorporateInvoicing.run(tenant, Date.add(late, 7))

    assert [%{status: "overdue", reminder_count: 2}] =
             Finance.list_corporate_invoices(context, client.id)
  end
end
