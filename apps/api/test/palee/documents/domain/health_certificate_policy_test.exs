defmodule Palee.Documents.Domain.HealthCertificatePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Documents.Domain.HealthCertificatePolicy, as: Policy

  @today ~D[2027-02-08]

  test "a certificate is valid for the box's months from its issue date by default" do
    assert {:ok, %{issued_on: ~D[2027-01-10], expires_on: ~D[2028-01-10]}} =
             Policy.validate_dates("2027-01-10", nil, @today, 12)

    assert {:ok, %{expires_on: ~D[2027-07-10]}} =
             Policy.validate_dates(~D[2027-01-10], nil, @today, 6)

    assert {:ok, %{expires_on: ~D[2027-06-30]}} =
             Policy.validate_dates("2027-01-10", "2027-06-30", @today, 12)
  end

  test "dates are checked" do
    assert {:error, {:invalid_fields, %{issued_on: "required"}}} =
             Policy.validate_dates(nil, nil, @today, 12)

    assert {:error, {:invalid_fields, %{issued_on: "invalid"}}} =
             Policy.validate_dates("10/01/2027", nil, @today, 12)

    assert {:error, {:invalid_fields, %{issued_on: "in_future"}}} =
             Policy.validate_dates("2027-02-09", nil, @today, 12)

    assert {:error, {:invalid_fields, %{expires_on: "before_issue"}}} =
             Policy.validate_dates("2027-01-10", "2027-01-10", @today, 12)

    assert {:error, {:invalid_fields, %{expires_on: "too_late"}}} =
             Policy.validate_dates("2027-01-10", "2029-02-10", @today, 12)

    assert {:error, {:invalid_fields, %{expires_on: "already_expired"}}} =
             Policy.validate_dates("2026-01-10", nil, @today, 12)
  end

  test "status: missing, valid, expiring within the reminder window, expired on the expiry day" do
    assert Policy.status(nil, @today, 30) == "missing"
    assert Policy.status(%{expires_on: ~D[2027-06-01]}, @today, 30) == "valid"
    assert Policy.status(%{expires_on: ~D[2027-03-10]}, @today, 30) == "expiring"
    assert Policy.status(%{expires_on: @today}, @today, 30) == "expired"
    assert Policy.usable?("expiring")
    refute Policy.usable?("expired")
    refute Policy.usable?("missing")
  end

  test "a reminder is due once per expiry date" do
    certificate = %{expires_on: ~D[2027-03-01], reminded_for: nil}
    assert Policy.reminder_due?(certificate, @today, 30)
    refute Policy.reminder_due?(%{certificate | reminded_for: ~D[2027-03-01]}, @today, 30)
    refute Policy.reminder_due?(%{certificate | expires_on: ~D[2027-06-01]}, @today, 30)
  end

  test "uploads are PDFs or photos of up to 10 MB, checked by their first bytes" do
    assert {:ok, %{extension: ".pdf", max_bytes: 10_485_760}} =
             Policy.validate_upload("application/pdf")

    assert {:error, {:invalid_fields, %{content_type: "unsupported"}}} =
             Policy.validate_upload("image/gif")

    assert :ok = Policy.validate_file("application/pdf", "%PDF-1.7\n", 1_000)
    assert :ok = Policy.validate_file("image/jpeg", <<0xFF, 0xD8, 0xFF, 0xE0>>, 1_000)
    assert :ok = Policy.validate_file("image/png", <<0x89, "PNG", 13, 10>>, 1_000)
    assert :ok = Policy.validate_file("image/webp", "RIFF" <> <<0, 0, 0, 0>> <> "WEBPVP8 ", 1_000)

    assert {:error, :health_certificate_file_invalid} =
             Policy.validate_file("application/pdf", <<0x89, "PNG">>, 1_000)

    assert {:error, :health_certificate_file_invalid} =
             Policy.validate_file("application/pdf", "%PDF-", 11 * 1024 * 1024)
  end

  test "upload keys live under the owner's folder" do
    key = "organizations/o/" <> Policy.relative_key("u1", ".pdf")
    assert Policy.key_of?(key, "organizations/o/", "u1")
    refute Policy.key_of?(key, "organizations/o/", "u2")
    refute Policy.key_of?(key, "organizations/other/", "u1")
    refute Policy.key_of?(nil, "organizations/o/", "u1")
  end
end
