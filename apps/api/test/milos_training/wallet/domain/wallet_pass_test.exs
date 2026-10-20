defmodule MilosTraining.Wallet.Domain.WalletPassTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Wallet.Domain.{ApplePass, GooglePass, PassContent, PassImage, PassToken}

  @key :crypto.strong_rand_bytes(32)
  @serial "3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"

  defp content(overrides \\ []) do
    struct!(
      PassContent,
      Keyword.merge(
        [
          serial: @serial,
          box: %{name: "Iron Box", slug: "iron", primary_color: "#FF6600"},
          member: %{name: "Μαρία Π."},
          barcode: PassToken.sign(@key, @serial),
          next_booking: %{
            name: "WOD",
            starts_at: ~U[2026-10-21 07:00:00Z],
            place: "Κεντρικό",
            label: "Τρ 21/10 10:00"
          },
          locations: [%{latitude: 37.98, longitude: 23.72, name: "Κεντρικό"}],
          locale: "el"
        ],
        overrides
      )
    )
  end

  @apple %{
    pass_type_identifier: "pass.test.milos",
    team_identifier: "TEAM123456",
    web_service_url: "https://api.example.test/api/wallet/apple",
    authentication_token: String.duplicate("a", 32)
  }

  describe "pass token" do
    test "round-trips the serial and rejects forgeries" do
      token = PassToken.sign(@key, @serial)

      assert PassToken.pass_token?(token)
      assert {:ok, @serial} = PassToken.verify(@key, token)
      assert {:error, :invalid_pass} = PassToken.verify(:crypto.strong_rand_bytes(32), token)
      assert {:error, :invalid_pass} = PassToken.verify(@key, "W1" <> "AAAA")
      assert {:error, :invalid_pass} = PassToken.verify(@key, "M1abc")
      refute PassToken.pass_token?("M1abc")
    end
  end

  describe "Apple pass.json" do
    test "is a generic pass with the barcode, the next booking and the web service" do
      pass = ApplePass.pass_json(content(), @apple)

      assert pass["formatVersion"] == 1
      assert pass["passTypeIdentifier"] == "pass.test.milos"
      assert pass["teamIdentifier"] == "TEAM123456"
      assert pass["serialNumber"] == @serial
      assert pass["organizationName"] == "Iron Box"
      assert pass["webServiceURL"] == @apple.web_service_url
      assert pass["authenticationToken"] == @apple.authentication_token
      assert pass["backgroundColor"] == "rgb(255, 102, 0)"
      assert pass["voided"] == false
      assert [%{"format" => "PKBarcodeFormatQR", "message" => "W1" <> _}] = pass["barcodes"]
      assert [%{"key" => "member", "value" => "Μαρία Π."}] = pass["generic"]["primaryFields"]

      assert [
               %{"key" => "next", "value" => "2026-10-21T07:00:00Z"},
               %{"key" => "class", "value" => "WOD · Κεντρικό"}
             ] =
               pass["generic"]["secondaryFields"]

      assert pass["relevantDate"] == "2026-10-21T07:00:00Z"
      assert [%{"latitude" => 37.98}] = pass["locations"]
    end

    test "without a booking, revoked, in English" do
      pass =
        ApplePass.pass_json(
          content(next_booking: nil, revoked?: true, locale: "en", locations: []),
          @apple
        )

      assert [%{"key" => "next", "value" => "No booking"}] = pass["generic"]["secondaryFields"]
      assert pass["voided"] == true
      refute Map.has_key?(pass, "relevantDate")
      refute Map.has_key?(pass, "locations")
    end

    test "the manifest lists the SHA-1 of every file" do
      images = PassImage.images("#FF6600")
      files = ApplePass.files(content(), @apple, images)
      manifest = files |> ApplePass.manifest() |> Jason.decode!()

      assert Enum.map(files, &elem(&1, 0)) == Enum.sort(["pass.json" | Map.keys(images)])
      assert "icon.png" in Map.keys(manifest)

      for {name, bytes} <- files do
        assert manifest[name] == :crypto.hash(:sha, bytes) |> Base.encode16(case: :lower)
      end
    end

    test "generated images are valid PNGs and a PNG logo is used as is" do
      for {_name, bytes} <- PassImage.images(nil), do: assert(PassImage.png?(bytes))

      logo = PassImage.solid_png(10, 10, {1, 2, 3})
      assert %{"logo.png" => ^logo} = PassImage.images("#000000", logo)
      assert PassImage.parse_color("#0A0B0C") == {10, 11, 12}
    end
  end

  describe "Google save JWT" do
    test "claims have the save-to-wallet shape" do
      google = %{
        issuer_id: "3388000000012345678",
        service_account_email: "wallet@project.iam.gserviceaccount.com",
        origins: ["https://app.example.test"],
        logo_url: "https://cdn.example.test/logo.png"
      }

      claims = GooglePass.save_claims(content(), google, ~U[2026-10-20 18:00:00Z])

      assert claims["iss"] == google.service_account_email
      assert claims["aud"] == "google"
      assert claims["typ"] == "savetowallet"
      assert claims["iat"] == 1_792_519_200
      assert claims["origins"] == ["https://app.example.test"]

      assert [%{"id" => "3388000000012345678.milos_member_card"}] =
               claims["payload"]["genericClasses"]

      assert [object] = claims["payload"]["genericObjects"]
      assert object["id"] == "3388000000012345678." <> @serial
      assert object["classId"] == "3388000000012345678.milos_member_card"
      assert object["state"] == "ACTIVE"
      assert object["barcode"] == %{"type" => "QR_CODE", "value" => content().barcode}
      assert object["hexBackgroundColor"] == "#FF6600"
      assert object["logo"]["sourceUri"]["uri"] == google.logo_url
      assert object["header"]["defaultValue"]["value"] == "Μαρία Π."

      assert [%{"id" => "next", "body" => "Τρ 21/10 10:00 · WOD · Κεντρικό"} | _] =
               object["textModulesData"]

      assert GooglePass.save_url("abc") == "https://pay.google.com/gp/v/save/abc"
    end

    test "a revoked pass is inactive" do
      assert %{"state" => "INACTIVE"} = GooglePass.generic_object(content(revoked?: true), "1")
    end
  end
end
