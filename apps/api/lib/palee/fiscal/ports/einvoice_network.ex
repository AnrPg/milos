defmodule Palee.Fiscal.Ports.EInvoiceNetwork do
  @moduledoc """
  Sends structured invoices over an e-invoicing network (Peppol, ADR-250)
  through an access point. One adapter per access point: `Sandbox` (no
  network, for pilots and tests) and `FiskalyEInvoice` (fiskaly
  E-INVOICE, the default since 2026-10-29); others can follow behind the
  same port.

  `connection` is the organization's network connection with its
  decrypted credentials (`%{environment, provider, api_key, api_secret,
  legal_entity_id, peppol_scheme, peppol_identifier}`; for fiskaly the
  key and secret may be those of the business's fiskaly till
  connection).

  `submit/2` takes `%{ubl, document, original, document_type,
  idempotency_guid, recipient}`: the UBL element tree of
  `Fiscal.Domain.UblInvoice.build/2` (already valid BIS 3.0), the fiscal
  document itself (for access points that build the e-invoice from
  fields, like fiskaly), the corrected invoice of a credit note
  (`%{number, issue_date, submission_id}` or nil), `"Invoice"` or
  `"CreditNote"`, the GUID that makes a resend harmless and the
  receiver's `%{scheme, identifier}`.

  Errors:
    * `{:rejected, [%{code, message}]}` – the access point refused it;
    * `{:unauthorized, reason}` – the credentials were refused;
    * `{:uncertain, reason}` – it may have arrived (timeout, dropped
      connection, idempotency GUID already used): never resent by itself;
    * anything else is transient (network down before sending, 5xx, 429).

  `status/2` reads a submission's delivery: `{:ok, :delivered}`,
  `{:ok, :in_progress}` or `{:ok, {:failed, errors}}`.

  Every call also returns what went over the wire, for the attempt log
  (credentials are never part of it):
  `%{request_body, response_status, response_body}`.
  """

  @type connection :: %{
          required(:environment) => String.t(),
          required(:provider) => String.t(),
          optional(:api_key) => String.t() | nil,
          optional(:api_secret) => String.t() | nil,
          optional(:legal_entity_id) => String.t() | nil,
          optional(:peppol_scheme) => String.t(),
          optional(:peppol_identifier) => String.t()
        }
  @type submission :: %{
          required(:ubl) => tuple(),
          optional(:document) => map(),
          optional(:original) => map() | nil,
          required(:document_type) => String.t(),
          required(:idempotency_guid) => String.t(),
          required(:recipient) => %{scheme: String.t(), identifier: String.t()}
        }
  @type wire :: %{
          request_body: String.t() | nil,
          response_status: non_neg_integer() | nil,
          response_body: String.t() | nil
        }

  @callback submit(connection(), submission()) ::
              {{:ok, %{submission_id: String.t()}} | {:error, term()}, wire()}

  @callback status(connection(), submission_id :: String.t()) ::
              {{:ok, :delivered | :in_progress | {:failed, list()}} | {:error, term()}, wire()}
end
