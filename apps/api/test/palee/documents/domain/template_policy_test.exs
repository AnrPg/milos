defmodule Palee.Documents.Domain.TemplatePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Documents.Domain.{SettingsPolicy, StarterTemplates, TemplatePolicy}

  describe "templates" do
    test "a document needs a known kind and a title; it is optional unless staff say otherwise" do
      assert {:ok, %{kind: "waiver", title: "Απαλλαγή", requirement: "optional"}} =
               TemplatePolicy.validate_template(%{kind: "waiver", title: "  Απαλλαγή "})

      assert {:ok, %{requirement: "mandatory"}} =
               TemplatePolicy.validate_template(%{
                 kind: "terms",
                 title: "Όροι",
                 requirement: "mandatory"
               })

      assert {:error, {:invalid_fields, errors}} =
               TemplatePolicy.validate_template(%{kind: "contract", title: "", requirement: "x"})

      assert errors == %{kind: "invalid", title: "required", requirement: "invalid"}

      assert {:error, {:invalid_fields, %{title: "too_long"}}} =
               TemplatePolicy.validate_template(%{
                 kind: "other",
                 title: String.duplicate("α", 201)
               })
    end

    test "the requirement is mandatory or optional" do
      assert {:ok, "mandatory"} = TemplatePolicy.validate_requirement("mandatory")

      assert {:error, {:invalid_fields, %{requirement: "invalid"}}} =
               TemplatePolicy.validate_requirement("sometimes")
    end
  end

  describe "versions" do
    test "the first version is always major; later ones default to major" do
      assert {:ok, %{change_kind: "major", language: "el"}} =
               TemplatePolicy.validate_version(
                 %{title: "Όροι", body: "Κείμενο", change_kind: "minor"},
                 1
               )

      assert {:ok, %{change_kind: "major"}} =
               TemplatePolicy.validate_version(%{title: "Όροι", body: "Κείμενο"}, 2)

      assert {:ok, %{change_kind: "minor", language: "en"}} =
               TemplatePolicy.validate_version(
                 %{title: "Terms", body: "Text", language: "en", change_kind: "minor"},
                 3
               )
    end

    test "the body is required, bounded and its line endings normalised" do
      assert {:error, {:invalid_fields, %{body: "required"}}} =
               TemplatePolicy.validate_version(%{title: "T", body: "  "}, 1)

      assert {:error, {:invalid_fields, %{body: "too_long"}}} =
               TemplatePolicy.validate_version(
                 %{title: "T", body: String.duplicate("a", 100_001)},
                 1
               )

      assert {:ok, %{body: "a\nb\nc"}} =
               TemplatePolicy.validate_version(%{title: "T", body: "a\r\nb\rc\n"}, 1)

      assert {:error, {:invalid_fields, %{language: "invalid", change_kind: "invalid"}}} =
               TemplatePolicy.validate_version(
                 %{title: "T", body: "x", language: "xx", change_kind: "huge"},
                 2
               )
    end

    test "a major version moves the required version, a minor one keeps it" do
      template = %{current_version_number: 2, required_version_number: 1}

      assert TemplatePolicy.next_numbers(template, "major") ==
               %{current_version_number: 3, required_version_number: 3}

      assert TemplatePolicy.next_numbers(template, "minor") ==
               %{current_version_number: 3, required_version_number: 1}
    end

    test "the content hash covers the exact text and changes with any of it" do
      version = %{
        template_id: "0b9a4f2e-6d1c-4d8e-9a77-2f0a5c3e1b11",
        number: 1,
        title: "Όροι",
        language: "el",
        body: "Κείμενο"
      }

      hash = TemplatePolicy.content_hash(version)
      assert hash =~ ~r/^[0-9a-f]{64}$/
      assert hash == TemplatePolicy.content_hash(version)
      refute hash == TemplatePolicy.content_hash(%{version | body: "Κείμενο."})
      refute hash == TemplatePolicy.content_hash(%{version | number: 2})
      refute hash == TemplatePolicy.content_hash(%{version | title: "Όροι."})
    end
  end

  describe "settings" do
    test "defaults block booking on unsigned documents only" do
      assert SettingsPolicy.effective(nil) == %{
               block_booking_on_unsigned: true,
               health_certificate_required: false,
               block_booking_on_health_certificate: false,
               health_certificate_validity_months: 12,
               health_certificate_reminder_days: 30
             }
    end

    test "blocking on health certificates turns on requiring them; values are checked" do
      assert {:ok,
              %{block_booking_on_health_certificate: true, health_certificate_required: true}} =
               SettingsPolicy.validate(nil, %{block_booking_on_health_certificate: true})

      assert {:error,
              {:invalid_fields,
               %{
                 health_certificate_validity_months: "invalid",
                 block_booking_on_unsigned: "invalid"
               }}} =
               SettingsPolicy.validate(nil, %{
                 health_certificate_validity_months: 36,
                 block_booking_on_unsigned: "yes"
               })

      assert SettingsPolicy.changed(SettingsPolicy.defaults(), %{
               SettingsPolicy.defaults()
               | health_certificate_reminder_days: 14
             }) == [:health_certificate_reminder_days]
    end
  end

  describe "starter templates" do
    test "Greek and English drafts of the four documents, all marked for legal review" do
      starters = StarterTemplates.list()
      assert length(starters) == 8

      for starter <- starters do
        assert starter.draft and starter.legal_review_required
        assert starter.body =~ ~r/ΠΡΟΣΧΕΔΙΟ ΓΙΑ ΝΟΜΙΚΟ ΕΛΕΓΧΟ|DRAFT FOR LEGAL REVIEW/
        assert {:ok, _} = TemplatePolicy.validate_template(starter)
        assert {:ok, _} = TemplatePolicy.validate_version(starter, 1)
      end

      assert %{title: "Υπεύθυνη δήλωση υγείας", requirement: "optional"} =
               StarterTemplates.get("health_certificate", "el")

      assert length(StarterTemplates.list("en")) == 4
    end
  end
end
