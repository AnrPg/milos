defmodule PaleeWeb.DeskCollectControllerTest do
  @moduledoc """
  ADR-272 end to end: «Είσπραξη» on the staff phone. Availability says why
  not; «Ποιος;» finds today's check-ins, the box's buyers and, by exact
  email only, an account outside the box; front desk makes a person or a
  walk-in a guest of the box and sells them a πακέτο συνδρομής; the result
  carries the receipt (number, transmission, a walk-in's open link) and
  the receipt can be emailed; a tip belongs to whoever started the payment
  on their phone, or to the front desk; Finance sums tips per person.
  """
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures

  alias Palee.{Facility, Finance, Fiscal, Organizations}
  alias Palee.Payments.PaymentStore

  @identity %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    street: "Ερμού",
    postal_code: "10563",
    city: "Αθήνα"
  }

  setup do
    owner = admin_fixture(%{nickname: "desk_owner"})
    desk = user_fixture(%{nickname: "desk_eleni", display_name: "Ελένη Υποδοχή"})
    member =
      user_fixture(%{
        nickname: "desk_maria",
        display_name: "Μαρία Κωνσταντίνου",
        email: "maria#{System.unique_integer([:positive])}@example.com"
      })

    {:ok, organization} =
      Organizations.create_organization(%{name: "Desk Tenant #{System.unique_integer([:positive])}"})

    add(organization, owner, [:owner])
    add(organization, desk, [:front_desk])
    add(organization, member, [:member])
    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, _membership} =
      Finance.upsert_membership(context, member.id, %{
        user_type_snapshot: "member",
        status: "active",
        signup_source: "admin_created"
      })

    %{owner: owner, desk: desk, member: member, organization: organization, context: context}
  end

  defp add(organization, user, roles) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: hd(roles),
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp admin_path(ctx, rest), do: "/api/org/#{ctx.organization.slug}/admin/payments#{rest}"
  defp as(conn, user), do: put_bearer_token(conn, user)

  defp connect_sandbox(conn, ctx) do
    conn
    |> as(ctx.owner)
    |> put(admin_path(ctx, "/account"), %{provider: "sandbox", environment: "test"})
    |> json_response(200)
  end

  defp start(conn, ctx, user, body) do
    conn
    |> as(user)
    |> post(
      admin_path(ctx, "/terminal"),
      Map.put_new(body, :idempotency_key, "desk-" <> Ecto.UUID.generate())
    )
    |> json_response(201)
    |> Map.fetch!("payment")
  end

  defp complete(conn, ctx, user, payment, extras \\ %{}) do
    conn
    |> as(user)
    |> post(
      admin_path(ctx, "/terminal/#{payment["id"]}/sandbox-complete"),
      Map.put(extras, :outcome, "succeeded")
    )
    |> json_response(200)
    |> Map.fetch!("payment")
  end

  describe "availability (ADR-272)" do
    test "says why Tap to Pay is not possible", %{conn: conn} = ctx do
      availability = fn ->
        conn |> as(ctx.desk) |> get(admin_path(ctx, "/terminal/availability")) |> json_response(200)
      end

      assert %{"available" => false, "reason" => "no_viva", "provider" => nil} = availability.()

      {:ok, _account} =
        PaymentStore.save_account(ctx.context, %{
          provider: "stripe",
          environment: "test",
          status: "active",
          credentials: %{"secret_key" => "sk_test"}
        })

      assert %{"available" => false, "reason" => "stripe_only", "provider" => "stripe"} =
               availability.()

      connect_sandbox(conn, ctx)
      assert %{"available" => true, "reason" => nil} = availability.()
    end
  end

  describe "the receipt on the result screen" do
    test "a walk-in's sale: its receipt, an open link for the QR, and the email",
         %{conn: conn} = ctx do
      connect_sandbox(conn, ctx)

      {:ok, _identity} =
        Fiscal.save_identity(ctx.context, @identity, ctx.owner.id, DateTime.utc_now())

      payment =
        start(conn, ctx, ctx.desk, %{
          purpose: "free_sale",
          amount_cents: 1_200,
          description: "Day pass"
        })

      assert payment["document"] == nil
      assert payment["started_on"] == "phone"
      assert payment["started_by_id"] == ctx.desk.id

      paid = complete(conn, ctx, ctx.desk, payment, %{tip_cents: 500})

      assert paid["status"] == "succeeded"
      assert %{"number" => number, "kind" => "receipt", "receipt_url" => url} = paid["document"]
      assert is_binary(number)
      assert paid["document"]["gross_cents"] == 1_200
      assert url =~ "/api/public/receipts/"

      # The tip is the desk person's, who started the payment on their phone.
      assert paid["tip_cents"] == 500
      assert paid["tip_attribution"] == "started_payment"
      assert paid["tip_recipient_user_id"] == ctx.desk.id

      # The QR's link opens the receipt; a changed token opens nothing.
      path = URI.parse(url).path
      html = conn |> get(path) |> response(200)
      assert html =~ number

      conn |> get(path <> "x") |> response(404)

      # A walk-in's receipt by email needs an address.
      email_path = admin_path(ctx, "/terminal/#{paid["id"]}/receipt-email")

      assert %{"code" => "no_recipient"} =
               conn
               |> as(ctx.desk)
               |> post(email_path, %{idempotency_key: "walk-in-mail-1"})
               |> json_response(422)

      assert %{"email" => %{"to" => "walkin@example.com", "recipient" => "address"}} =
               conn
               |> as(ctx.desk)
               |> post(email_path, %{idempotency_key: "walk-in-mail-2", to: "walkin@example.com"})
               |> json_response(202)
    end

    test "a member's receipt has no open link and is emailed to their account",
         %{conn: conn} = ctx do
      connect_sandbox(conn, ctx)

      {:ok, _identity} =
        Fiscal.save_identity(ctx.context, @identity, ctx.owner.id, DateTime.utc_now())

      payment =
        start(conn, ctx, ctx.desk, %{
          purpose: "free_sale",
          user_id: ctx.member.id,
          amount_cents: 3_000,
          description: "Personal training"
        })

      paid = complete(conn, ctx, ctx.desk, payment)
      assert %{"receipt_url" => nil, "number" => _number} = paid["document"]
      assert paid["tip_attribution"] == nil

      assert %{"email" => %{"to" => to}} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/terminal/#{paid["id"]}/receipt-email"), %{
                 idempotency_key: "member-mail-1"
               })
               |> json_response(202)

      assert to == ctx.member.email
    end
  end

  describe "tips (ADR-272)" do
    test "a desk payment's tip is the only front desk person's; owners never count",
         %{conn: conn} = ctx do
      connect_sandbox(conn, ctx)
      # The owner also holds the front desk role: still not counted.
      {:ok, _owner} = Organizations.set_membership_roles(ctx.context, ctx.owner.id, [:owner, :front_desk])

      payment =
        start(conn, ctx, ctx.owner, %{
          purpose: "free_sale",
          user_id: ctx.member.id,
          amount_cents: 2_000,
          description: "Day pass",
          started_on: "desk"
        })

      paid = complete(conn, ctx, ctx.owner, payment, %{tip_cents: 300})
      assert paid["started_on"] == "desk"
      assert paid["tip_attribution"] == "sole_front_desk"
      assert paid["tip_recipient_user_id"] == ctx.desk.id

      # A second front desk person: the next desk tip is the role's.
      other = user_fixture(%{nickname: "desk_nikos"})
      add(ctx.organization, other, [:front_desk])

      second =
        start(conn, ctx, ctx.owner, %{
          purpose: "free_sale",
          user_id: ctx.member.id,
          amount_cents: 1_000,
          description: "Νερό",
          started_on: "desk"
        })

      paid_second = complete(conn, ctx, ctx.owner, second, %{tip_cents: 100})
      assert paid_second["tip_attribution"] == "front_desk_role"
      assert paid_second["tip_recipient_role"] == "front_desk"
      assert paid_second["tip_recipient_user_id"] == nil

      # A phone payment by the second person is theirs.
      third =
        start(conn, ctx, other, %{
          purpose: "free_sale",
          amount_cents: 500,
          description: "Νερό"
        })

      complete(conn, ctx, other, third, %{tip_cents: 50})

      summary =
        conn |> as(ctx.owner) |> get(admin_path(ctx, "/tips")) |> json_response(200)

      assert summary["total_cents"] == 450

      by_kind = Enum.map(summary["rows"], &{&1["kind"], &1["user_id"], &1["tip_cents"]})
      assert {"person", ctx.desk.id, 300} in by_kind
      assert {"front_desk_role", nil, 100} in by_kind
      assert {"person", other.id, 50} in by_kind

      # The desk can take payments, not read the tips report.
      conn |> as(ctx.desk) |> get(admin_path(ctx, "/tips")) |> json_response(403)

      assert %{"code" => "tips_period_invalid"} =
               conn
               |> as(ctx.owner)
               |> get(admin_path(ctx, "/tips?from=2027-02-01&to=2027-01-01"))
               |> json_response(422)
    end
  end

  describe "«Ποιος;» and guests of the box (ADR-272)" do
    test "today's check-ins, the box's buyers by name, outsiders by exact email only",
         %{conn: conn} = ctx do
      today = Organizations.local_today(ctx.organization.id, DateTime.utc_now())

      {:ok, _check_in} =
        Facility.create_check_in(ctx.context, %{
          organization_id: ctx.organization.id,
          user_id: ctx.member.id,
          checked_in_on: today,
          checked_in_at: DateTime.utc_now(),
          source: "staff"
        })

      people = fn query ->
        conn
        |> as(ctx.desk)
        |> get(admin_path(ctx, "/desk/people") <> query)
        |> json_response(200)
        |> Map.fetch!("people")
      end

      assert [%{"user_id" => member_id, "relation" => "member", "checked_in_at" => at}] =
               people.("")

      assert member_id == ctx.member.id
      assert is_binary(at)

      # Accents and case do not matter.
      assert [%{"user_id" => ^member_id}] = people.("?q=μαρια")

      outsider = user_fixture(%{nickname: "desk_outsider", email: "out#{System.unique_integer([:positive])}@example.com"})
      assert people.("?q=desk_outsider") == []
      assert [%{"user_id" => outsider_id, "relation" => "none"}] = people.("?q=" <> outsider.email)
      assert outsider_id == outsider.id
    end

    test "front desk makes a person a guest and sells them a package; guests see no member content",
         %{conn: conn} = ctx do
      connect_sandbox(conn, ctx)
      guest = user_fixture(%{nickname: "desk_guest"})

      assert %{"added" => true, "created_profile" => false, "person" => %{"relation" => "guest"}} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/desk/guests"), %{user_id: guest.id})
               |> json_response(201)

      # Again: nothing changes.
      assert %{"added" => false} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/desk/guests"), %{user_id: guest.id})
               |> json_response(200)

      assert Organizations.member_roles(ctx.organization.id, guest.id) == [:guest]

      {:ok, package} =
        Finance.create_package(ctx.context, %{
          name: "12 επισκέψεις",
          package_type: "class_pack",
          base_price_cents: 9_000
        })

      assert %{"options" => %{"relation" => "guest", "packages" => packages}} =
               conn
               |> as(ctx.desk)
               |> get(admin_path(ctx, "/desk/options?user_id=#{guest.id}"))
               |> json_response(200)

      assert Enum.any?(packages, &(&1["id"] == package.id and &1["price_cents"] == 9_000))

      payment =
        start(conn, ctx, ctx.desk, %{
          purpose: "membership_package",
          purpose_id: package.id,
          user_id: guest.id,
          amount_cents: 9_000
        })

      assert %{"status" => "succeeded", "fulfilment_status" => "done"} =
               complete(conn, ctx, ctx.desk, payment)

      assert %{active_package_subscription: %{}} = Finance.get_member_profile(ctx.context, guest.id)

      # The box is not one of the guest's gyms: no member app, no club, no console.
      memberships = conn |> as(guest) |> get("/api/memberships") |> json_response(200)
      refute Enum.any?(memberships, &(&1["organization"]["id"] == ctx.organization.id))

      assert %{"boxes" => [%{"id" => box_id, "slug" => slug}]} =
               conn |> as(guest) |> get("/api/memberships/guest-boxes") |> json_response(200)

      assert box_id == ctx.organization.id
      assert slug == ctx.organization.slug

      # A guest takes no payments.
      conn
      |> as(guest)
      |> get(admin_path(ctx, "/terminal/availability"))
      |> json_response(403)
    end

    test "a walk-in signs up at the desk with a name and an email", %{conn: conn} = ctx do
      email = "walkin#{System.unique_integer([:positive])}@example.com"

      assert %{"added" => true, "created_profile" => true, "person" => person} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/desk/guests"), %{name: "Γιώργος Επισκέπτης", email: email})
               |> json_response(201)

      assert person["name"] == "Γιώργος Επισκέπτης"
      assert person["relation"] == "guest"
      assert %{membership: %{}} = Finance.get_member_profile(ctx.context, person["user_id"])

      assert %{"code" => "guest_email_invalid"} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/desk/guests"), %{name: "Χ", email: "not-an-email"})
               |> json_response(422)

      assert %{"code" => "guest_name_required"} =
               conn
               |> as(ctx.desk)
               |> post(admin_path(ctx, "/desk/guests"), %{name: " ", email: email})
               |> json_response(422)

      # Staff are not made guests.
      assert %{"code" => "guest_is_staff"} =
               conn
               |> as(ctx.owner)
               |> post(admin_path(ctx, "/desk/guests"), %{user_id: ctx.desk.id})
               |> json_response(409)
    end
  end
end
