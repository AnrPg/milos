defmodule Palee.Infrastructure.Payments.SandboxGateway do
  @moduledoc """
  A payment provider that is not there (ADR-246), for development, tests
  and demos. No network and no state: references are signed with a key
  derived from the endpoint secret, so only Palee's own sandbox page
  (`complete/3`) can turn a checkout into a paid one.

  Enabled only where `config :palee, :payments_sandbox` is true (dev and
  test), so a live business can never take sandbox «payments».

  A checkout whose description contains `decline` saves a card that is
  always declined later, for trying the dunning schedule.
  """

  @behaviour Palee.Payments.Ports.Gateway

  alias Palee.Infrastructure.Payments.Http

  @impl true
  def credential_keys, do: []
  @impl true
  def setting_keys, do: []

  def enabled?, do: Application.get_env(:palee, :payments_sandbox, false) == true

  @impl true
  def check(_account), do: if(enabled?(), do: :ok, else: {:error, {:invalid, :sandbox_disabled}})

  @impl true
  def create_checkout(_account, request) do
    ref = "sbxo_" <> request.reference
    separator = if String.contains?(request.return_url, "?"), do: "&", else: "?"
    declines = if request.description =~ ~r/decline/i, do: "1", else: "0"

    {:ok,
     %{
       provider_ref: ref,
       redirect_url:
         request.return_url <>
           separator <>
           URI.encode_query(%{"sandbox_checkout" => ref, "sandbox_decline" => declines})
     }}
  end

  @doc """
  What the sandbox page does when the payer presses pay or cancel: the
  transaction id to bring back to the return page.
  """
  def complete(provider_ref, outcome, decline_card? \\ false)
      when outcome in ["succeeded", "failed", "cancelled"] do
    body = Enum.join([provider_ref, outcome, if(decline_card?, do: "d", else: "k")], ".")
    "sbxt_" <> Base.url_encode64(body, padding: false) <> "." <> sign(body)
  end

  @impl true
  def fetch_payment(_account, %{transaction_id: "sbxt_" <> _rest = transaction_id} = query) do
    case verify(transaction_id) do
      {:ok, [ref, outcome, card]} when ref == query.provider_ref or is_nil(query.provider_ref) ->
        {:ok, payment(outcome, transaction_id, card)}

      _invalid ->
        {:error, {:invalid, :unknown_transaction}}
    end
  end

  def fetch_payment(_account, %{transaction_id: "sbxc_" <> _rest = transaction_id}),
    do: {:ok, %{status: :succeeded, transaction_id: transaction_id}}

  def fetch_payment(_account, _query), do: {:ok, %{status: :pending, transaction_id: nil}}

  defp payment(outcome, transaction_id, card) do
    %{
      status: String.to_existing_atom(outcome),
      transaction_id: transaction_id,
      amount_cents: nil,
      currency: nil,
      card: %{brand: "visa", last4: "4242", exp_month: 12, exp_year: 2099},
      method_token: "sbxm_" <> card <> "_" <> binary_part(sign(transaction_id), 0, 16),
      failure:
        if(outcome == "succeeded",
          do: nil,
          else: %{code: "sandbox_#{outcome}", message: "Sandbox #{outcome}"}
        )
    }
  end

  @impl true
  def charge_saved(_account, "sbxm_d_" <> _rest, _request),
    do: {:error, {:declined, "card_declined", "Sandbox card declined"}}

  def charge_saved(_account, "sbxm_" <> _rest, request) do
    {:ok,
     %{
       status: :succeeded,
       transaction_id: "sbxc_" <> binary_part(sign(request.idempotency_key), 0, 24),
       amount_cents: request.amount_cents,
       currency: request.currency
     }}
  end

  def charge_saved(_account, _token, _request), do: {:error, {:invalid, :unknown_token}}

  @impl true
  def refund(_account, request) do
    {:ok,
     %{
       provider_ref: "sbxr_" <> binary_part(sign(request.idempotency_key), 0, 24),
       status: :succeeded
     }}
  end

  @impl true
  def parse_webhook(_account, %{method: "POST", headers: headers, body: body}) do
    with signature when is_binary(signature) <- Http.header(headers, "x-sandbox-signature"),
         true <- Plug.Crypto.secure_compare(signature, sign(body)) do
      case Jason.decode(body) do
        {:ok, %{"event_id" => id} = event} when is_binary(id) ->
          {:ok,
           [
             %{
               event_id: id,
               type: event["type"] || "payment",
               provider_ref: event["provider_ref"],
               transaction_id: event["transaction_id"]
             }
           ]}

        _other ->
          {:error, :invalid_payload}
      end
    else
      _bad -> {:error, :invalid_signature}
    end
  end

  def parse_webhook(_account, _request), do: {:reply, 200, %{}}

  @doc false
  def sign(body) do
    key = :crypto.mac(:hmac, :sha256, secret_base(), "palee-payments-sandbox")
    :hmac |> :crypto.mac(:sha256, key, body) |> Base.url_encode64(padding: false)
  end

  defp verify("sbxt_" <> token) do
    with [encoded, signature] <- String.split(token, ".", parts: 2),
         {:ok, body} <- Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(signature, sign(body)),
         [_ref, _outcome, _card] = parts <- String.split(body, ".") do
      {:ok, parts}
    else
      _invalid -> :error
    end
  end

  defp secret_base do
    :palee
    |> Application.get_env(PaleeWeb.Endpoint, [])
    |> Keyword.get(:secret_key_base, "palee-dev-sandbox")
  end
end
