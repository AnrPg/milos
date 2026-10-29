defmodule Palee.Infrastructure.Payments.StripeConnect do
  @moduledoc """
  Stripe Connect OAuth for Standard accounts (ADR-261): the owner signs in
  to (or opens) their own Stripe account and allows Palee; Stripe returns a
  code that Palee exchanges for the account id (`acct_…`). Payments are
  then made with Palee's platform key and the `Stripe-Account` header, so
  the money goes straight to the business's account.

  Platform credentials per environment (`config :palee, :stripe_connect`):
  `client_id` (`ca_…`) and `secret_key` (`sk_test_…` / `sk_live_…`).

  Sources: docs.stripe.com/connect/oauth-standard-accounts and
  docs.stripe.com/connect/oauth-reference (authorize, token, deauthorize).
  """

  @behaviour Palee.Payments.Ports.Connect

  alias Palee.Infrastructure.Payments.Http

  @connect "https://connect.stripe.com"

  @doc "The platform's secret key for an environment, or nil."
  def platform_key(environment), do: platform(environment)[:secret_key]

  defp platform(environment) do
    :palee
    |> Application.get_env(:stripe_connect, %{})
    |> Map.get(environment, %{})
    |> Map.new(fn {key, value} -> {key, value} end)
  end

  @impl true
  def available?(environment) do
    config = platform(environment)
    present?(config[:client_id]) and present?(config[:secret_key])
  end

  defp present?(value), do: is_binary(value) and value != ""

  @impl true
  def authorize_url(environment, request) do
    if available?(environment) do
      query =
        [
          response_type: "code",
          client_id: platform(environment)[:client_id],
          scope: "read_write",
          state: request.state,
          redirect_uri: request.redirect_uri
        ]
        |> prefill("stripe_user[email]", request[:email])
        |> prefill("stripe_user[business_name]", request[:business_name])
        |> prefill("stripe_user[country]", request[:country])

      {:ok, @connect <> "/oauth/authorize?" <> URI.encode_query(query)}
    else
      {:error, :connect_not_configured}
    end
  end

  defp prefill(query, _key, value) when value in [nil, ""], do: query
  defp prefill(query, key, value), do: query ++ [{key, value}]

  @impl true
  def complete(_environment, %{"error" => "access_denied"}), do: {:error, :access_denied}

  def complete(environment, %{"code" => code}) when is_binary(code) and code != "" do
    case Http.request(
           method: :post,
           url: @connect <> "/oauth/token",
           auth: {:bearer, platform_key(environment) || ""},
           form: [grant_type: "authorization_code", code: code]
         ) do
      {:ok, %{status: 200, body: %{"stripe_user_id" => "acct_" <> _ = account} = body}} ->
        if live_matches?(body["livemode"], environment),
          do: {:ok, %{connected_account: account}},
          else: {:error, :environment_mismatch}

      {:ok, %{status: status, body: %{"error" => "invalid_grant"}}} when status in 400..499 ->
        {:error, :invalid_grant}

      {:ok, %{status: status}} when status in [401, 403] ->
        {:error, {:unauthorized, {:http, status}}}

      {:ok, %{status: status}} ->
        {:error, {:transient, {:http, status}}}

      {:error, _reason} = error ->
        error
    end
  end

  def complete(_environment, _params), do: {:error, :invalid_grant}

  defp live_matches?(livemode, "live"), do: livemode == true
  defp live_matches?(livemode, _test), do: livemode != true

  @impl true
  def disconnect(environment, "acct_" <> _ = account) do
    case Http.request(
           method: :post,
           url: @connect <> "/oauth/deauthorize",
           auth: {:bearer, platform_key(environment) || ""},
           form: [client_id: platform(environment)[:client_id], stripe_user_id: account]
         ) do
      {:ok, %{status: 200}} -> :ok
      # Already disconnected by the owner on Stripe's side.
      {:ok, %{status: 400}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http, status}}
      {:error, _reason} = error -> error
    end
  end

  def disconnect(_environment, _account), do: :ok
end
