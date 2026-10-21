defmodule Palee.Infrastructure.Wallet.WalletSigningTest do
  # Touches the global :wallet config, so not async.
  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Wallet.{
    ApplePassBuilder,
    Der,
    GooglePassBuilder,
    Pkcs7Signer
  }

  alias Palee.Wallet.Domain.PassContent

  @moduletag :tmp_dir

  defp test_ca(key_spec) do
    %{cert: cert, key: key} =
      :public_key.pkix_test_root_cert(~c"Palee Wallet Test", [{:key, key_spec}])

    {cert, key}
  end

  defp cert_pem(der), do: :public_key.pem_encode([{:Certificate, der, :not_encrypted}])

  defp key_pem(key),
    do: :public_key.pem_encode([:public_key.pem_entry_encode(elem(key, 0), key)])

  defp content do
    %PassContent{
      serial: Ecto.UUID.generate(),
      box: %{name: "Iron Box", slug: "iron"},
      member: %{name: "Maria"},
      barcode: "W1test",
      next_booking: nil
    }
  end

  setup do
    previous = Application.get_env(:palee, :wallet)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :wallet, previous),
        else: Application.delete_env(:palee, :wallet)
    end)

    :ok
  end

  # Checks the signature the way Wallet does: the signed attributes carry
  # the manifest's SHA-256 and verify against the certificate's key, and the
  # certificate travels in the signature.
  defp verify_in_elixir(signature, manifest, cert_der) do
    {0x30, outer, _whole, ""} = Der.read(signature)
    [_oid, {0xA0, explicit}] = parts(outer)
    [{0x30, signed_data}] = parts(explicit)
    [_version, _digests, _content, {0xA0, certs}, {0x31, signer_infos}] = parts(signed_data)

    assert cert_der in Der.children(certs)

    [{0x30, signer_info}] = parts(signer_infos)
    [_v, _sid, _alg, {0xA0, attrs}, _sig_alg, {0x04, sig}] = parts(signer_info)

    assert :binary.match(attrs, :crypto.hash(:sha256, manifest)) != :nomatch
    assert :public_key.verify(Der.tlv(0x31, attrs), :sha256, sig, public_key(cert_der))
  end

  defp parts(content) do
    content
    |> Der.children()
    |> Enum.map(fn whole ->
      {tag, inner, _whole, _rest} = Der.read(whole)
      {tag, inner}
    end)
  end

  defp public_key(cert_der) do
    {:OTPCertificate, tbs, _alg, _sig} = :public_key.pkix_decode_cert(cert_der, :otp)
    {:OTPSubjectPublicKeyInfo, algorithm, key} = elem(tbs, 7)

    case algorithm do
      {:PublicKeyAlgorithm, _oid, {:namedCurve, curve}} -> {key, {:namedCurve, curve}}
      _rsa -> key
    end
  end

  defp openssl_verify(dir, signature, manifest, cert_der) do
    case System.find_executable("openssl") do
      nil ->
        :skipped

      openssl ->
        File.write!(Path.join(dir, "signature"), signature)
        File.write!(Path.join(dir, "manifest.json"), manifest)
        File.write!(Path.join(dir, "ca.pem"), cert_pem(cert_der))

        {output, status} =
          System.cmd(
            openssl,
            ~w(cms -verify -binary -inform DER -in signature -content manifest.json -CAfile ca.pem -purpose any -out /dev/null),
            cd: dir,
            stderr_to_stdout: true
          )

        assert status == 0, output
    end
  end

  for {name, spec} <- [rsa: {:rsa, 2048, 17}, ec: {:namedCurve, :secp256r1}] do
    test "the PKCS#7 detached signature verifies (#{name} key)", %{tmp_dir: dir} do
      {cert, key} = test_ca(unquote(Macro.escape(spec)))
      manifest = ~s({"pass.json":"abc"})

      signature = Pkcs7Signer.sign(manifest, cert, key, [], ~U[2026-10-20 18:00:00Z])

      verify_in_elixir(signature, manifest, cert)
      openssl_verify(dir, signature, manifest, cert)

      refute :binary.match(signature, :crypto.hash(:sha256, manifest <> "x")) != :nomatch
    end
  end

  test "Apple builder without credentials is not configured" do
    Application.put_env(:palee, :wallet, apple: [], google: [])

    refute ApplePassBuilder.configured?()
    assert {:error, :wallet_not_configured} = ApplePassBuilder.build(content(), %{})
    refute GooglePassBuilder.configured?()
    assert {:error, :wallet_not_configured} = GooglePassBuilder.build(content(), %{})
  end

  test "Apple builder makes a signed .pkpass from PEM text or files", %{tmp_dir: dir} do
    {cert, key} = test_ca({:rsa, 2048, 17})
    key_path = Path.join(dir, "key.pem")
    File.write!(key_path, key_pem(key))

    Application.put_env(:palee, :wallet,
      apple: [
        pass_type_identifier: "pass.test.palee",
        team_identifier: "TEAM123456",
        certificate: cert_pem(cert),
        private_key: key_path,
        wwdr_certificate: cert_pem(cert)
      ]
    )

    assert ApplePassBuilder.configured?()

    assert {:ok, %{kind: :pkpass, body: body}} =
             ApplePassBuilder.build(content(), %{
               web_service_url: "https://api.example.test/api/wallet/apple",
               authentication_token: String.duplicate("t", 32),
               images: %{"icon.png" => "png-bytes"}
             })

    {:ok, entries} = :zip.unzip(body, [:memory])
    files = Map.new(entries, fn {name, bytes} -> {to_string(name), bytes} end)

    assert Map.keys(files) |> Enum.sort() == [
             "icon.png",
             "manifest.json",
             "pass.json",
             "signature"
           ]

    assert %{"serialNumber" => _, "passTypeIdentifier" => "pass.test.palee"} =
             Jason.decode!(files["pass.json"])

    manifest = Jason.decode!(files["manifest.json"])
    assert manifest["icon.png"] == :crypto.hash(:sha, "png-bytes") |> Base.encode16(case: :lower)

    verify_in_elixir(files["signature"], files["manifest.json"], cert)
    openssl_verify(dir, files["signature"], files["manifest.json"], cert)
  end

  test "Google builder signs an RS256 save JWT with the service account key" do
    {_cert, key} = test_ca({:rsa, 2048, 17})

    Application.put_env(:palee, :wallet,
      google: [
        issuer_id: "3388000000012345678",
        service_account_email: "wallet@project.iam.gserviceaccount.com",
        private_key: key_pem(key),
        origins: ["https://app.example.test"]
      ]
    )

    assert GooglePassBuilder.configured?()

    assert {:ok, %{kind: :save_link, url: "https://pay.google.com/gp/v/save/" <> jwt}} =
             GooglePassBuilder.build(content(), %{now: ~U[2026-10-20 18:00:00Z]})

    [header, _payload, _sig] = String.split(jwt, ".")
    assert %{"alg" => "RS256"} = header |> Base.url_decode64!(padding: false) |> Jason.decode!()

    public = key |> JOSE.JWK.from_key() |> JOSE.JWK.to_public()

    assert {true, %JOSE.JWT{fields: claims}, _jws} =
             JOSE.JWT.verify_strict(public, ["RS256"], jwt)

    assert claims["typ"] == "savetowallet"
    assert claims["aud"] == "google"
    assert claims["iat"] == 1_792_519_200

    class_id = Palee.Wallet.Domain.GooglePass.class_id("3388000000012345678")

    assert [%{"classId" => ^class_id}] =
             claims["payload"]["genericObjects"]
  end
end
