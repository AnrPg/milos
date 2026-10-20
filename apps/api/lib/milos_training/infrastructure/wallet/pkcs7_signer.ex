defmodule MilosTraining.Infrastructure.Wallet.Pkcs7Signer do
  @moduledoc """
  A detached CMS (PKCS#7) SignedData signature, as Apple Wallet wants for a
  pass's `manifest.json` (ADR-155): SHA-256, signed attributes (content
  type, signing time, message digest), the pass type certificate and the
  Apple WWDR intermediate in `certificates`, and the signer identified by
  issuer and serial number. Built with Erlang's `:public_key`/`:crypto` and a
  small DER encoder; RSA and EC keys are supported.
  """

  alias MilosTraining.Infrastructure.Wallet.Der

  @signed_data "1.2.840.113549.1.7.2"
  @data "1.2.840.113549.1.7.1"
  @sha256 "2.16.840.1.101.3.4.2.1"
  @rsa "1.2.840.113549.1.1.1"
  @ecdsa_sha256 "1.2.840.10045.4.3.2"
  @content_type "1.2.840.113549.1.9.3"
  @message_digest "1.2.840.113549.1.9.4"
  @signing_time "1.2.840.113549.1.9.5"

  @doc """
  Signs `content` (detached). `certificate` is the signer's DER certificate,
  `key` its decoded private key (`:public_key.pem_entry_decode/2`), `chain`
  further DER certificates (the WWDR intermediate).
  """
  def sign(content, certificate, key, chain, %DateTime{} = signed_at) do
    {issuer, serial} = Der.issuer_and_serial(certificate)
    digest_algorithm = Der.sequence([Der.oid(@sha256), Der.null()])

    attributes =
      Der.set([
        attribute(@content_type, Der.oid(@data)),
        attribute(@signing_time, Der.utc_time(signed_at)),
        attribute(@message_digest, Der.octet_string(:crypto.hash(:sha256, content)))
      ])

    signature = :public_key.sign(attributes, :sha256, key)

    signer_info =
      Der.sequence([
        Der.integer(1),
        Der.sequence([issuer, serial]),
        digest_algorithm,
        Der.implicit_constructed(0, attributes),
        signature_algorithm(key),
        Der.octet_string(signature)
      ])

    signed_data =
      Der.sequence([
        Der.integer(1),
        Der.set([digest_algorithm]),
        Der.sequence([Der.oid(@data)]),
        Der.implicit_constructed(0, Der.set([certificate | chain])),
        Der.set([signer_info])
      ])

    Der.sequence([Der.oid(@signed_data), Der.explicit(0, signed_data)])
  end

  defp attribute(type, value), do: Der.sequence([Der.oid(type), Der.set([value])])

  defp signature_algorithm(key) when elem(key, 0) == :ECPrivateKey,
    do: Der.sequence([Der.oid(@ecdsa_sha256)])

  defp signature_algorithm(_rsa_key), do: Der.sequence([Der.oid(@rsa), Der.null()])
end
