defmodule Palee.Imports.PeopleImportsTest do
  @moduledoc """
  ADR-254 end to end under Row Level Security: upload, dry run, apply,
  retry and re-import without duplicates, matching by email and phone,
  payments as history and visits, the demo gate, invitations, undo, held
  profiles and tenant isolation.
  """

  use Palee.DataCase, async: false
  use Palee.EmailCase

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 1]

  alias Palee.Application.Imports.PeopleImports
  alias Palee.{Facility, Finance, Fiscal, Identity, Imports, Organizations}

  @csv """
  Όνομα;Επώνυμο;Email;Κινητό;Πακέτο;Τιμή;Έναρξη;Λήξη;Υπόλοιπο;Ποσό;Ημερομηνία πληρωμής;Τρόπος πληρωμής;Ημερομηνία επίσκεψης
  Μαρία;Παπαδοπούλου;maria@import.test;6941111111;Μηνιαίο;50,00;01/01/2027;31/12/2027;20;50;05/01/2027;Μετρητά;10/01/2027
  Νίκος;Γεωργίου;;+30 694 222 2222;Μηνιαίο;50,00;01/01/2027;31/01/2027;;;;;
  Μαρία;Παπαδοπούλου;maria@import.test;6941111111;Μηνιαίο;50,00;01/01/2027;31/12/2027;20;50;05/01/2027;Μετρητά;10/01/2027
  ;;;;;;;;;;;;
  ;;not-an-email;;;;;;;;;;
  Μαρία;Παπαδοπούλου;maria@import.test;;;;;;;;;;11/01/2027
  """

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    %{organization: organization, owner: owner, context: context}
  end

  defp upload(context, csv, opts \\ []) do
    path = Path.join(System.tmp_dir!(), "import-#{System.unique_integer([:positive])}.csv")
    encoding = Keyword.get(opts, :encoding, :utf8)

    content =
      case encoding do
        :utf8 -> csv
        :utf16le -> <<0xFF, 0xFE>> <> :unicode.characters_to_binary(csv, :utf8, {:utf16, :little})
      end

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    {:ok, import} =
      PeopleImports.upload(context, %{filename: "members.csv", path: path}, opts[:source])

    import
  end

  defp outcomes(context, import_id) do
    {:ok, %{rows: rows}} = PeopleImports.rows(context, import_id, %{"limit" => 500})
    Enum.map(rows, &{&1.row_number, &1.status, &1.outcome})
  end

  test "upload detects the encoding, delimiter and a mapping", %{context: context} do
    import = upload(context, @csv, encoding: :utf16le)

    assert %{
             status: "draft",
             source: "excel",
             encoding: "utf16le",
             delimiter: ";",
             row_count: 5,
             date_order: "dmy"
           } = import

    fields = Enum.map(import.mapping, & &1.field)

    assert fields == ~w(first_name last_name email phone package_name package_price
                        package_starts_on package_ends_on credit_balance payment_amount
                        payment_date payment_method visit_date)

    # The all-empty line is dropped.
    assert import.counts.statuses == %{"pending" => 5}
  end

  test "the dry run plans every row and writes nothing outside imports", %{context: context} do
    {member, _member_context} = bypass_rls(fn -> member_context(context.organization) end)
    member_email = Identity.find_by_id(member.id).email

    csv = @csv <> "Eleni;Member;#{member_email};;;;;;;;;;\n"
    import = upload(context, csv)

    assert {:ok, previewed} = PeopleImports.preview(context, import.id, %{})

    assert outcomes(context, import.id) == [
             {1, "pending", "create_person"},
             {2, "pending", "create_person"},
             {3, "pending", "duplicate_row"},
             {4, "pending", "invalid"},
             {5, "pending", "update_person"},
             {6, "pending", "update_person"}
           ]

    assert previewed.preview.outcomes == %{
             "create_person" => 2,
             "duplicate_row" => 1,
             "invalid" => 1,
             "update_person" => 2
           }

    assert previewed.preview.warnings["invalid_email"] == 1
    assert previewed.preview.warnings["package_created"] == 1
    assert Identity.profiles_by_emails(["maria@import.test"]) == %{}
    assert [] = Finance.list_packages(context)
  end

  test "the mapping and options can change while it is a draft", %{context: context} do
    import = upload(context, "Email,Joined\nann@import.test,02/03/2027\n")

    assert {:ok, %{date_order: "mdy", default_role: "athlete"}} =
             PeopleImports.preview(context, import.id, %{
               "mapping" => [
                 %{"column" => 0, "field" => "email"},
                 %{"column" => 1, "field" => "joined_on"}
               ],
               "date_order" => "mdy",
               "default_role" => "athlete"
             })

    assert {:error, :invalid_mapping} =
             PeopleImports.preview(context, import.id, %{
               "mapping" => [%{"column" => 0, "field" => "notes"}]
             })

    assert {:error, :invalid_date_order} =
             PeopleImports.preview(context, import.id, %{"date_order" => "dym"})
  end

  test "apply writes through each context; a retry and a re-import create nothing twice",
       %{context: context} do
    import = upload(context, @csv)
    {:ok, _} = PeopleImports.preview(context, import.id, %{})

    assert {:ok, applied} = PeopleImports.apply(context, import.id)
    assert applied.status == "applied"
    assert applied.finished_at

    assert outcomes(context, import.id) == [
             {1, "applied", "create_person"},
             {2, "applied", "create_person"},
             {3, "skipped", "already_imported"},
             {4, "skipped", "invalid"},
             {5, "applied", "update_person"}
           ]

    assert %{
             "people_created" => 2,
             "packages_created" => 1,
             "subscriptions" => 2,
             "credits" => 1,
             "payments" => 1,
             "visits" => 2
           } = applied.summary

    # Maria: a held profile with her email, a member, her package, credit,
    # payment (history, no fiscal document) and two visits.
    %{"maria@import.test" => [%{id: maria, held_by_organization_id: held}]} =
      Identity.profiles_by_emails(["maria@import.test"])

    assert held == context.organization_id

    assert Organizations.member_roles(context.organization_id, maria) |> Enum.map(&to_string/1) ==
             ["member"]

    profile = Finance.get_member_profile(context, maria)
    assert profile.membership.signup_source == "imported"

    assert [%{price_cents_snapshot: 5000, ends_on: ~D[2027-12-31]}] =
             profile.package_subscriptions

    assert profile.credit_balance == 2000

    assert [%{amount_cents: 5000, payment_method: "cash", paid_on: ~D[2027-01-05]}] =
             profile.payments

    assert Fiscal.list_documents(context).documents == []

    visits = Facility.list_check_ins(context, %{user_id: maria})
    assert visits |> Enum.map(& &1.method) |> Enum.uniq() == ["imported"]

    assert visits |> Enum.map(& &1.checked_in_on) |> Enum.sort() == [
             ~D[2027-01-10],
             ~D[2027-01-11]
           ]

    # Nikos has no email: a placeholder login that never receives mail.
    %{user_id: nikos} = Imports.find_person(context, :phone_key, "6942222222")
    assert Identity.find_by_id(nikos).email =~ "@import.palee.invalid"

    # No email went out.
    assert enqueued_emails(organization_id: context.organization_id) == []

    # A retry applies nothing new.
    assert {:ok, %{status: "applied"}} = PeopleImports.apply(context, import.id)
    assert length(Finance.get_member_profile(context, maria).payments) == 1

    # The same file again: every row is already imported.
    again = upload(context, @csv)
    {:ok, again_applied} = PeopleImports.apply(context, again.id)
    assert again_applied.summary["people_created"] == 0
    assert again_applied.summary["payments"] == 0

    # Rows 1, 2, 3 (the in-file repeat of 1) and 5 were applied before.
    assert Enum.count(outcomes(context, again.id), &match?({_, _, "already_imported"}, &1)) == 4
    assert length(Finance.get_member_profile(context, maria).payments) == 1
    assert Finance.get_member_profile(context, maria).credit_balance == 2000
  end

  test "people are matched by email, then by phone across files", %{context: context} do
    first = upload(context, "Name,Email,Phone\nAnna Lee,anna@import.test,+1 415 555 0100\n")
    {:ok, _} = PeopleImports.apply(context, first.id)
    %{user_id: anna} = Imports.find_person(context, :email, "anna@import.test")

    second =
      upload(
        context,
        "Name,Phone,Payment amount,Payment date\nAnna L.,(415) 555-0100,30,2027-01-02\n"
      )

    {:ok, applied} = PeopleImports.apply(context, second.id)
    assert applied.summary["people_created"] == 0
    assert [%{user_id: ^anna, outcome: "update_person"}] = rows(context, second.id)
    assert [%{amount_cents: 3000}] = Finance.get_member_profile(context, anna).payments
  end

  test "a staff member matched by email gets no finance records", %{
    context: context,
    owner: owner
  } do
    email = Identity.find_by_id(owner.id).email
    import = upload(context, "Name,Email,Amount,Payment date\nOwner,#{email},10,2027-01-01\n")
    {:ok, _} = PeopleImports.apply(context, import.id)

    assert [
             %{
               status: "applied",
               outcome: "update_person",
               warnings: [%{"code" => "not_a_client"}]
             }
           ] =
             rows(context, import.id)

    assert Finance.get_member_profile(context, owner.id) == nil
  end

  test "an email of an account outside the business never links that account",
       %{context: context} do
    outsider = Palee.TestFixtures.user_fixture(%{email: "outsider@import.test"})
    import = upload(context, "Name,Email\nOut Sider,outsider@import.test\n")

    {:ok, previewed} = PeopleImports.preview(context, import.id, %{})
    assert previewed.preview.outcomes == %{"create_person" => 1}

    {:ok, _} = PeopleImports.apply(context, import.id)
    assert Organizations.member_roles(context.organization_id, outsider.id) == []
    %{user_id: held} = Imports.find_person(context, :email, "outsider@import.test")
    refute held == outsider.id
    assert Identity.find_by_id(held).email =~ "@import.palee.invalid"
  end

  test "held profiles stay hidden until the person proves the inbox", %{context: context} do
    import = upload(context, "Name,Email\nHidden Person,hidden@import.test\n")
    {:ok, _} = PeopleImports.apply(context, import.id)
    %{user_id: held} = Imports.find_person(context, :email, "hidden@import.test")
    stranger = Palee.TestFixtures.user_fixture()

    assert Identity.visible_user_ids([held], stranger.id) == []
    assert Identity.visible_user_ids([held], context.user_id) == [held]

    account = Identity.find_by_id(held)
    assert :ok = Identity.mark_email_verified(account.login_id, "hidden@import.test")
    refute Identity.held_user?(Identity.find_by_id(held))
    assert Identity.visible_user_ids([held], stranger.id) == [held]
  end

  test "a demo business may upload and dry-run but not apply or invite", %{context: context} do
    bypass_rls(fn ->
      Palee.Repo.query!(
        "UPDATE organizations SET activation = 'demo', provider_kind = 'gym' WHERE id = $1",
        [Ecto.UUID.dump!(context.organization_id)]
      )
    end)

    demo = put_in(context.organization.activation, "demo")
    import = upload(demo, "Name,Email\nDemo Person,demo@import.test\n")

    assert {:ok, %{preview: %{outcomes: %{"create_person" => 1}}}} =
             PeopleImports.preview(demo, import.id, %{})

    assert {:error, :business_not_activated} = PeopleImports.apply(demo, import.id)
    assert {:error, :business_not_activated} = PeopleImports.invite(demo, import.id, %{})
    assert {:ok, %{status: "draft"}} = PeopleImports.show(demo, import.id)
  end

  test "invitations are an explicit step, once per person", %{context: context} do
    import = upload(context, @csv)
    assert {:error, :import_not_applied} = PeopleImports.invite(context, import.id, %{})
    {:ok, _} = PeopleImports.apply(context, import.id)

    assert {:ok, %{sent: 1, failed: 0, remaining: 0, results: [%{email: "maria@import.test"}]}} =
             PeopleImports.invite(context, import.id, %{})

    assert_email_enqueued(kind: :organization_invitation, to: "maria@import.test")
    assert {:ok, %{sent: 0, results: []}} = PeopleImports.invite(context, import.id, %{})
  end

  test "undo reverses what the import wrote", %{context: context} do
    import = upload(context, @csv)
    {:ok, _} = PeopleImports.apply(context, import.id)
    %{user_id: maria} = Imports.find_person(context, :email, "maria@import.test")

    assert {:ok, %{status: "undone", undone_at: %DateTime{}}} =
             PeopleImports.undo(context, import.id)

    assert Organizations.member_roles(context.organization_id, maria) == []
    assert Facility.list_check_ins(context, %{user_id: maria}) == []

    profile = Finance.get_member_profile(context, maria)
    assert profile.credit_balance == 0
    assert profile.payments == []
    assert Enum.all?(profile.package_subscriptions, &(&1.status == "cancelled"))

    assert {:error, :import_already_undone} = PeopleImports.undo(context, import.id)
    assert {:error, :import_already_applied} = PeopleImports.delete(context, import.id)
    assert Enum.all?(outcomes(context, import.id), &(elem(&1, 1) in ["undone", "skipped"]))

    # Undone rows free their fingerprints: importing again brings them back.
    again = upload(context, @csv)
    {:ok, applied} = PeopleImports.apply(context, again.id)
    assert applied.summary["people_created"] == 0
    assert applied.summary["memberships_added"] == 2
    assert Organizations.member_roles(context.organization_id, maria) != []
  end

  test "a draft can be deleted; another business sees nothing", %{context: context} do
    import = upload(context, "Name\nSomeone\n")
    {_other_org, _other_owner, other} = bypass_rls(fn -> organization_fixture() end)

    assert {:error, :not_found} = PeopleImports.show(other, import.id)
    assert {:error, :not_found} = PeopleImports.apply(other, import.id)
    assert PeopleImports.list(other) == []
    assert Imports.rows(other, import.id, %{limit: :all}) == []

    assert :ok = PeopleImports.delete(context, import.id)
    assert {:error, :not_found} = PeopleImports.show(context, import.id)
  end

  test "upload errors", %{context: context} do
    path = Path.join(System.tmp_dir!(), "empty-#{System.unique_integer([:positive])}.csv")
    File.write!(path, "Name,Email\n")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :no_rows} =
             PeopleImports.upload(context, %{filename: "x.csv", path: path}, nil)

    assert {:error, :invalid_source} =
             PeopleImports.upload(context, %{filename: "x.csv", path: path}, "mindbody")

    assert {:error, :import_file_missing} = PeopleImports.upload(context, nil, nil)
  end

  defp rows(context, import_id), do: Imports.rows(context, import_id, %{limit: :all})
end
