defmodule Palee.Infrastructure.Fiscal.SandboxEInvoiceNetwork do
  @moduledoc """
  A Peppol access point that is not there (ADR-250): takes every
  well-formed invoice and "delivers" it without the network. Used by the
  `sandbox` environment (pilots before a business has an access point,
  demos, development) and by tests.

  Submission ids start with `sandbox-` so they can never be mistaken for
  real ones, and the same GUID always gets the same id. A receiver whose
  identifier is the Belgian enterprise number `0000000097` is "not on
  Peppol": its delivery fails, so the failure path can be tried.
  """

  @behaviour Palee.Fiscal.Ports.EInvoiceNetwork

  alias Palee.Infrastructure.Fiscal.Peppol.UblWriter

  @unreachable "0000000097"

  @impl true
  def submit(_connection, %{ubl: ubl, idempotency_guid: guid, recipient: recipient}) do
    body = UblWriter.write(ubl)
    {_root, children} = ubl

    result =
      if Enum.any?(children, &match?({line, _} when line in ["cac:InvoiceLine", "cac:CreditNoteLine"], &1)) do
        id =
          if recipient.identifier == @unreachable,
            do: "sandbox-unreachable-" <> guid,
            else: "sandbox-" <> guid

        {:ok, %{submission_id: id}}
      else
        {:error, {:rejected, [%{code: "sandbox", message: "Document without lines"}]}}
      end

    {result, %{request_body: body, response_status: nil, response_body: nil}}
  end

  @impl true
  def status(_connection, "sandbox-unreachable-" <> _guid) do
    {{:ok, {:failed, [%{code: "sandbox", message: "The receiver is not on Peppol"}]}},
     %{request_body: nil, response_status: nil, response_body: nil}}
  end

  def status(_connection, _submission_id),
    do: {{:ok, :delivered}, %{request_body: nil, response_status: nil, response_body: nil}}
end
