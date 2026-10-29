defmodule Palee.Fiscal.Ports.CashRegisterSecurity do
  @moduledoc """
  Signs till receipts with the cash-register security device the law of
  the country asks for (ADR-251): a cloud TSE in Germany (KassenSichV),
  a signature creation unit in Austria (RKSV). One adapter per provider
  and device: `Sandbox` (no network, both devices), `FiskalySignDe` (SIGN
  DE v2) and `FiskalySignAt` (SIGN AT).

  `connection` is the organization's till connection with its decrypted
  credentials (`%{device, environment, api_key, api_secret, admin_pin,
  unit_id, register_id, unit_serial, register_serial}`); `unit_id` is the
  TSS (DE) or signature creation unit (AT), `register_id` the client (DE)
  or cash register (AT). Both ids are chosen by Palee, so every call is
  addressed to a known resource and can be read back.

  `provision/2` creates and initialises the unit and the register (and,
  in Austria, signs the start receipt) and returns
  `%{unit_serial, register_serial, public_key, admin_pin, start}` (any of
  them may be nil). `context` carries the business's legal name and VAT
  id.

  `sign/2` takes `%{external_id, kind, schema}`: Palee's id for the
  transaction or receipt, `"receipt"` or `"null"`, and the process data of
  `Domain.TseTransaction` / `Domain.RksvReceipt`. `lookup/2` reads the
  transaction or receipt with that id back (and, for a German transaction
  left open, finishes it): `{:error, :not_found}` when the device never
  saw it.

  A signature: `%{transaction_number, signature_counter, signature_value,
  signature_algorithm, time_format, started_at_device, finished_at_device,
  unit_serial, register_serial, receipt_number, qr_code_data,
  device_failed, hint}`; times come from the device, not from Palee.

  Errors: `{:rejected, errors}`, `{:unauthorized, reason}`,
  `{:uncertain, reason}` (may have reached the device) or anything else
  (transient). Every call returns what went over the wire (never the
  credentials): `%{request_body, response_status, response_body}`.
  """

  @type wire :: %{
          request_body: String.t() | nil,
          response_status: non_neg_integer() | nil,
          response_body: String.t() | nil
        }

  @callback provision(connection :: map(), context :: map()) ::
              {{:ok, map()} | {:error, term()}, wire()}
  @callback sign(connection :: map(), request :: map()) ::
              {{:ok, map()} | {:error, term()}, wire()}
  @callback lookup(connection :: map(), request :: map()) ::
              {{:ok, map()} | {:error, term()}, wire()}

  @doc """
  «Δοκιμή σύνδεσης» (ADR-273): signs in with the connection's credentials
  and reads the unit and register Palee provisioned, without signing
  anything. `{:ok, %{}}`, `{:error, {:unauthorized, _}}` (credentials
  refused), `{:error, :unit_not_found}`, `{:error, :unit_not_ready}` or
  anything else (transient).
  """
  @callback check(connection :: map()) :: {:ok, map()} | {:error, term()}
end
