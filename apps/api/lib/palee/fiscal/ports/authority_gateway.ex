defmodule Palee.Fiscal.Ports.AuthorityGateway do
  @moduledoc """
  Reports fiscal documents to a tax authority (ADR-243). One adapter per
  channel: `Sandbox` (no network, for pilots and tests), `MyData` (AADE's
  REST API as an ERP), later a certified provider.

  `connection` is the organization's authority connection with its
  decrypted credentials (`%{environment, user_id, subscription_key}`).
  `invoice` is the element tree of `Fiscal.Domain.MyDataInvoice.build/2`.

  Errors:
    * `{:rejected, [%{code, message}]}` – the authority refused the content;
    * `{:unauthorized, reason}` – the credentials were refused;
    * anything else is transient (network, timeout, 5xx, technical error).

  A document is never cancelled at the authority: it is corrected with a
  credit note, which is reported like any other document (ADR-241).

  Every call also returns what went over the wire, for the attempt log:
  `%{request_body, response_status, response_body}`.
  """

  @type connection :: %{
          required(:environment) => String.t(),
          optional(:user_id) => String.t() | nil,
          optional(:subscription_key) => String.t() | nil
        }
  @type receipt :: %{
          mark: String.t(),
          uid: String.t() | nil,
          authentication_code: String.t() | nil,
          qr_url: String.t() | nil
        }
  @type wire :: %{
          request_body: String.t() | nil,
          response_status: non_neg_integer() | nil,
          response_body: String.t() | nil
        }

  @callback submit(connection(), invoice :: list()) ::
              {{:ok, receipt()} | {:error, term()}, wire()}
end
