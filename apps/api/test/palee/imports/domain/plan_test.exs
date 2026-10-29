defmodule Palee.Imports.Domain.PlanTest do
  use ExUnit.Case, async: true

  alias Palee.Imports.Domain.{Fields, HeaderMatcher, ImportPolicy, Presets, RowPlan}

  @options %{date_order: "dmy", default_role: "member"}

  describe "presets and the header matcher" do
    test "every preset names only catalog fields" do
      for preset <- Presets.all(), field <- Map.keys(preset.headers) do
        assert field in Fields.keys(), "#{preset.key}: #{field}"
      end
    end

    test "Greek generic headers map to fields" do
      %{source: "excel", mapping: mapping} =
        HeaderMatcher.suggest(["Όνομα", "Επώνυμο", "Κινητό", "E-mail", "Πακέτο", "Λήξη", "Χ"])

      assert Enum.map(mapping, & &1.field) ==
               ["first_name", "last_name", "phone", "email", "package_name", "package_ends_on", nil]
    end

    test "a vendor is detected and its date order proposed" do
      header = ["first_name", "last_name", "email", "plan_name", "Charge Amount", "customer_id"]
      assert %{source: "pushpress", date_order: "mdy", mapping: mapping} = HeaderMatcher.suggest(header)
      assert Enum.map(mapping, & &1.field) |> Enum.all?()

      # Generic names alone stay generic (dates day first).
      assert %{source: "excel", date_order: "dmy"} = HeaderMatcher.suggest(["Name", "Email"])
    end

    test "a field goes to one column only" do
      %{mapping: mapping} = HeaderMatcher.suggest(["Email", "E-mail"], "excel")
      assert Enum.map(mapping, & &1.field) == ["email", nil]
    end
  end

  describe "reading a row" do
    test "typed values, a display name and warnings for unreadable cells" do
      mapping = [
        %{column: 0, field: "first_name"},
        %{column: 1, field: "last_name"},
        %{column: 2, field: "email"},
        %{column: 3, field: "package_ends_on"},
        %{column: 4, field: "credit_balance"},
        %{column: 5, field: "payment_amount"}
      ]

      %{values: values, warnings: warnings} =
        RowPlan.read(["Μαρία", "Παπαδοπούλου", "not-an-email", "31/12/2025", "-5", "30"], mapping, @options)

      assert values["name"] == "Μαρία Παπαδοπούλου"
      assert values["package_ends_on"] == ~D[2025-12-31]
      assert values["role"] == "member"
      assert values["payment_amount"] == 3000
      refute Map.has_key?(values, "email")
      refute Map.has_key?(values, "credit_balance")

      assert Enum.map(warnings, & &1.code) ==
               ["invalid_email", "negative_balance", "payment_without_date"]
    end

    test "the fingerprint ignores case, accents and position" do
      a = RowPlan.fingerprint(%{"email" => "a@b.co", "name" => "Μαρία"})
      b = RowPlan.fingerprint(%{"name" => "ΜΑΡΙΑ", "email" => "a@b.co"})
      c = RowPlan.fingerprint(%{"name" => "Μαρία", "email" => "c@b.co"})
      assert a == b
      refute a == c
    end
  end

  describe "matching and planning" do
    test "email first, then phone; an account outside the business matches nobody" do
      index = %{
        members: %{"u-member" => true},
        profiles_by_email: %{"m@x.co" => ["u-member"], "outsider@x.co" => ["u-outside"]},
        people_by_phone: %{"6941234567" => "u-imported"}
      }

      assert {:member, "u-member", true} = RowPlan.match(%{"email" => "m@x.co"}, index)
      assert :new = RowPlan.match(%{"email" => "outsider@x.co"}, index)

      assert {:imported, "u-imported"} =
               RowPlan.match(%{"email" => "new@x.co", "phone" => "+30 6941234567"}, index)

      assert {:planned, 3} =
               RowPlan.match(%{"email" => "p@x.co"}, %{planned_by_email: %{"p@x.co" => 3}})
    end

    test "outcomes" do
      values = %{"name" => "Maria", "email" => "m@x.co", "role" => "member", "package_name" => "Monthly"}

      assert %{outcome: "create_person", actions: [:create_person, :finance_profile, :create_package, :assign_package]} =
               RowPlan.plan(values, %{person: :new})

      assert %{outcome: "update_person", actions: [:match_person, :finance_profile, :assign_package]} =
               RowPlan.plan(values, %{person: {:member, "u", true}, package_exists?: true})

      assert %{outcome: "update_person", actions: [:match_person], warnings: [%{code: "not_a_client"}]} =
               RowPlan.plan(values, %{person: {:member, "u", false}})

      assert %{outcome: "already_imported"} = RowPlan.plan(values, %{already_imported?: true})
      assert %{outcome: "duplicate_row"} = RowPlan.plan(values, %{duplicate_of: 2})

      assert %{outcome: "invalid", errors: [%{code: "missing_name"}]} =
               RowPlan.plan(%{"email" => "m@x.co", "role" => "member"}, %{person: :new})

      assert %{outcome: "invalid", errors: [%{code: "missing_person"}]} =
               RowPlan.plan(%{"role" => "member"}, %{person: :new})
    end

    test "what already exists is skipped with a warning" do
      values = %{
        "name" => "Maria",
        "role" => "member",
        "package_name" => "Monthly",
        "credit_balance" => 1000,
        "visit_date" => ~D[2025-01-02]
      }

      %{actions: actions, warnings: warnings} =
        RowPlan.plan(values, %{
          person: {:imported, "u"},
          subscription_exists?: true,
          credit_imported?: true,
          visit_exists?: true
        })

      assert actions == [:match_person, :finance_profile]

      assert Enum.map(warnings, & &1.code) ==
               ["subscription_exists", "credit_already_imported", "visit_exists"]
    end
  end

  describe "import policy" do
    test "limits" do
      assert {:error, :file_too_large} = ImportPolicy.check_size(5 * 1024 * 1024 + 1)
      assert :ok = ImportPolicy.check_size(5 * 1024 * 1024)
      assert {:error, :too_many_rows} = ImportPolicy.check_rows(20_001)
      assert {:error, :no_rows} = ImportPolicy.check_rows(0)
      assert ImportPolicy.invitation_batch(500) == 200
    end

    test "a mapping maps each field once and identifies people" do
      assert {:ok, [%{column: 0, field: "email"}]} =
               ImportPolicy.validate_mapping([%{"column" => 0, "field" => "email"}, %{column: 1, field: nil}], 2)

      assert {:error, :invalid_mapping} =
               ImportPolicy.validate_mapping([%{column: 0, field: "email"}, %{column: 1, field: "email"}], 2)

      assert {:error, :invalid_mapping} = ImportPolicy.validate_mapping([%{column: 0, field: "notes"}], 1)
      assert {:error, :invalid_mapping} = ImportPolicy.validate_mapping([%{column: 3, field: "email"}], 2)
      assert {:error, :invalid_mapping} = ImportPolicy.validate_mapping([%{column: 0, field: "age"}], 1)
    end

    test "transitions and the undo window" do
      finished = ~U[2027-02-01 10:00:00Z]
      assert :ok = ImportPolicy.can_apply(%{status: "draft"})
      assert :ok = ImportPolicy.can_apply(%{status: "failed"})
      assert {:error, :import_not_applicable} = ImportPolicy.can_apply(%{status: "undone"})
      assert {:error, :import_already_applied} = ImportPolicy.can_delete(%{status: "applied"})

      assert :ok =
               ImportPolicy.can_undo(%{status: "applied", finished_at: finished}, ~U[2027-02-08 10:00:00Z])

      assert {:error, :undo_window_closed} =
               ImportPolicy.can_undo(%{status: "applied", finished_at: finished}, ~U[2027-02-08 10:00:01Z])

      assert {:error, :import_already_undone} = ImportPolicy.can_undo(%{status: "undone"}, finished)
      assert {:error, :import_not_applied} = ImportPolicy.can_undo(%{status: "draft"}, finished)
    end
  end
end
