defmodule MilosTraining.Infrastructure.Wallet.ApplePassBuilder do
  @moduledoc """
  Apple adapter of `Wallet.Ports.PassBuilder` (ADR-155): pass.json and the
  images (`ApplePass.files/3`), manifest.json with each file's SHA-1, a
  detached PKCS#7 signature of the manifest with the pass type certificate
  (and the WWDR intermediate), zipped as a `.pkpass`.
  """

  @behaviour MilosTraining.Wallet.Ports.PassBuilder

  alias MilosTraining.Infrastructure.Wallet.{Credentials, Pkcs7Signer}
  alias MilosTraining.Wallet.Domain.ApplePass

  @impl true
  def configured?, do: match?({:ok, _credentials}, Credentials.apple())

  @impl true
  def build(content, opts) do
    with {:ok, credentials} <- Credentials.apple() do
      apple = %{
        pass_type_identifier: credentials.pass_type_identifier,
        team_identifier: credentials.team_identifier,
        web_service_url: opts.web_service_url,
        authentication_token: opts.authentication_token
      }

      files = ApplePass.files(content, apple, Map.get(opts, :images, %{}))
      manifest = ApplePass.manifest(files)

      signature =
        Pkcs7Signer.sign(
          manifest,
          credentials.certificate,
          credentials.private_key,
          [credentials.wwdr_certificate],
          Map.get(opts, :now) || DateTime.utc_now()
        )

      entries =
        Enum.map(
          files ++ [{"manifest.json", manifest}, {"signature", signature}],
          fn {name, bytes} -> {String.to_charlist(name), bytes} end
        )

      case :zip.create(~c"pass.pkpass", entries, [:memory]) do
        {:ok, {_name, body}} -> {:ok, %{kind: :pkpass, body: body}}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
