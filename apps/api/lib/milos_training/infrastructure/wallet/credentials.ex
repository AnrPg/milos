defmodule MilosTraining.Infrastructure.Wallet.Credentials do
  @moduledoc """
  Wallet credentials from runtime config (`config :milos_training, :wallet`),
  ADR-155. PEM values may be the PEM text itself or a path to a PEM file.

      apple: [pass_type_identifier, team_identifier, certificate, private_key,
              private_key_password (optional), wwdr_certificate, apns_host (optional)]
      google: [issuer_id, service_account_email, private_key, origins (optional)]

  Anything missing → `{:error, :wallet_not_configured}`.
  """

  @apple_required [
    :pass_type_identifier,
    :team_identifier,
    :certificate,
    :private_key,
    :wwdr_certificate
  ]
  @google_required [:issuer_id, :service_account_email, :private_key]

  def apple do
    with {:ok, config} <- section(:apple, @apple_required),
         {:ok, certificate} <- certificate(config[:certificate]),
         {:ok, wwdr} <- certificate(config[:wwdr_certificate]),
         {:ok, key} <- private_key(config[:private_key], config[:private_key_password]) do
      {:ok,
       %{
         pass_type_identifier: config[:pass_type_identifier],
         team_identifier: config[:team_identifier],
         certificate: certificate,
         wwdr_certificate: wwdr,
         private_key: key,
         apns_host: config[:apns_host] || "https://api.push.apple.com"
       }}
    end
  end

  def google do
    with {:ok, config} <- section(:google, @google_required),
         {:ok, pem} <- pem(config[:private_key]) do
      {:ok,
       %{
         issuer_id: config[:issuer_id],
         service_account_email: config[:service_account_email],
         private_key_pem: pem,
         origins: List.wrap(config[:origins])
       }}
    end
  end

  defp section(platform, required) do
    config = :milos_training |> Application.get_env(:wallet, []) |> Keyword.get(platform, [])

    if Enum.all?(required, &present?(config[&1])),
      do: {:ok, config},
      else: {:error, :wallet_not_configured}
  end

  defp certificate(value) do
    with {:ok, pem} <- pem(value),
         [{:Certificate, der, _encryption} | _] <- :public_key.pem_decode(pem) do
      {:ok, der}
    else
      _invalid -> {:error, :wallet_not_configured}
    end
  end

  defp private_key(value, password) do
    with {:ok, pem} <- pem(value),
         [entry | _] <- :public_key.pem_decode(pem) do
      {:ok, decode_key(entry, password)}
    else
      _invalid -> {:error, :wallet_not_configured}
    end
  rescue
    _error -> {:error, :wallet_not_configured}
  end

  defp decode_key(entry, nil), do: :public_key.pem_entry_decode(entry)
  defp decode_key(entry, ""), do: :public_key.pem_entry_decode(entry)

  defp decode_key(entry, password),
    do: :public_key.pem_entry_decode(entry, String.to_charlist(password))

  defp pem("-----BEGIN" <> _rest = pem), do: {:ok, pem}

  defp pem(path) when is_binary(path) do
    case File.read(path) do
      {:ok, "-----BEGIN" <> _rest = pem} -> {:ok, pem}
      _missing -> {:error, :wallet_not_configured}
    end
  end

  defp pem(_value), do: {:error, :wallet_not_configured}

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false
end
