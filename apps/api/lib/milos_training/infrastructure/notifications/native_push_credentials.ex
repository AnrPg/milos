defmodule MilosTraining.Infrastructure.Notifications.NativePushCredentials do
  @moduledoc """
  Native push credentials from runtime config (`config :milos_training,
  :native_push`), ADR-171. Values may be the text itself or a path to a file.

      fcm: [service_account (the Firebase service account JSON), req_options]
      apns: [team_id, key_id, private_key (the .p8 key), topic (bundle id),
             req_options]

  Anything missing or unreadable → `{:error, :native_push_not_configured}`.
  `req_options` exist for tests (a `Req.Test` plug) and are never set in
  production.
  """

  @not_configured {:error, :native_push_not_configured}

  def fcm do
    config = section(:fcm)

    with {:ok, text} <- read(config[:service_account]),
         {:ok, %{"project_id" => project, "client_email" => email, "private_key" => pem}}
         when is_binary(project) and is_binary(email) and is_binary(pem) <- Jason.decode(text),
         {:ok, jwk} <- jwk(pem) do
      {:ok,
       %{
         project_id: project,
         client_email: email,
         jwk: jwk,
         token_uri: "https://oauth2.googleapis.com/token",
         req_options: Keyword.get(config, :req_options, [])
       }}
    else
      _missing -> @not_configured
    end
  end

  def apns do
    config = section(:apns)

    with true <- present?(config[:team_id]) and present?(config[:key_id]),
         {:ok, pem} <- read(config[:private_key]),
         {:ok, jwk} <- jwk(pem) do
      {:ok,
       %{
         team_id: config[:team_id],
         key_id: config[:key_id],
         jwk: jwk,
         topic: presence(config[:topic]) || "app.milos.member",
         req_options: Keyword.get(config, :req_options, [])
       }}
    else
      _missing -> @not_configured
    end
  end

  defp section(provider),
    do: :milos_training |> Application.get_env(:native_push, []) |> Keyword.get(provider, [])

  defp read(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" -> @not_configured
      String.starts_with?(trimmed, ["{", "-----BEGIN"]) -> {:ok, trimmed}
      true -> read_file(trimmed)
    end
  end

  defp read(_value), do: @not_configured

  defp read_file(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, String.trim(text)}
      _missing -> @not_configured
    end
  end

  defp jwk(pem) do
    case JOSE.JWK.from_pem(pem) do
      %JOSE.JWK{} = jwk -> {:ok, jwk}
      _invalid -> @not_configured
    end
  rescue
    _error -> @not_configured
  end

  defp present?(value), do: presence(value) != nil

  defp presence(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp presence(_value), do: nil
end
