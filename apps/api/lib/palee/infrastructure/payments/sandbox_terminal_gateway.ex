defmodule Palee.Infrastructure.Payments.SandboxTerminalGateway do
  @moduledoc """
  A terminal app that is not there (ADR-249), for development, tests and
  demos: transaction ids are signed like the sandbox provider's
  (ADR-246), so only Palee's own sandbox step (`complete/3`) can make a
  «paid» one. Enabled only with `config :palee, :payments_sandbox`.
  """

  @behaviour Palee.Payments.Ports.TerminalGateway

  alias Palee.Infrastructure.Payments.SandboxGateway

  @outcomes ~w(succeeded failed cancelled)

  @impl true
  def app_request(_account, sale) do
    %{
      scheme: "palee-sandbox-terminal://pay/v1",
      params: %{
        "appId" => sale.app_id,
        "action" => "sale",
        "clientTransactionId" => sale.reference,
        "amount" => Integer.to_string(sale.amount_cents),
        "customerTrns" => sale.description,
        "callback" => sale.callback
      }
    }
  end

  @doc "The transaction id the sandbox terminal app would return for a sale."
  def complete(reference, outcome, amount_cents)
      when outcome in @outcomes and is_integer(amount_cents) do
    body = Enum.join([reference, outcome, amount_cents], "|")
    "sbxp_" <> Base.url_encode64(body, padding: false) <> "." <> SandboxGateway.sign(body)
  end

  @impl true
  def confirm(_account, "sbxp_" <> token = transaction_id) do
    with [encoded, signature] <- String.split(token, ".", parts: 2),
         {:ok, body} <- Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(signature, SandboxGateway.sign(body)),
         [reference, outcome, amount] when outcome in @outcomes <- String.split(body, "|") do
      {:ok,
       %{
         status: String.to_existing_atom(outcome),
         transaction_id: transaction_id,
         amount_cents: String.to_integer(amount),
         currency: nil,
         reference: reference,
         card: %{brand: "visa", last4: "4242", exp_month: nil, exp_year: nil},
         failure:
           if(outcome == "succeeded",
             do: nil,
             else: %{code: "sandbox_#{outcome}", message: "Sandbox #{outcome}"}
           )
       }}
    else
      _invalid -> {:error, {:invalid, :unknown_transaction}}
    end
  end

  def confirm(_account, _transaction_id), do: {:error, {:invalid, :unknown_transaction}}

  @impl true
  def find_by_reference(_account, _reference, _date), do: {:ok, nil}
end
