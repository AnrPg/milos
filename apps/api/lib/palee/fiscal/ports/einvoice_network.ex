defmodule Palee.Fiscal.Ports.EInvoiceNetwork do
  @moduledoc """
  Sends structured invoices over an e-invoicing network (Peppol, ADR-250)
  through an access point. One adapter per access point: `Sandbox` (no
  network, for pilots and tests) and `Storecove` (access point as a
  service); others can follow behind the same port.

  `connection` is the organization's network connection with its
  decrypted credentials (`%{environment, provider, api_key,
  legal_entity_id, peppol_scheme, peppol_identifier}`).

  `submit/2` takes `%{ubl, document_type, idempotency_guid, recipient}`:
  the UBL element tree of `Fiscal.Domain.UblInvoice.build/2`, `"Invoice"`
  or `"CreditNote"`, the GUID that makes a resend harmless and the
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
          optional(:legal_entity_id) => String.t() | nil,
          optional(:peppol_scheme) => String.t(),
          optional(:peppol_identifier) => String.t()
        }
  @type submission :: %{
          ubl: tuple(),
          document_type: String.t(),
          idempotency_guid: String.t(),
          recipient: %{scheme: String.t(), identifier: String.t()}
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
