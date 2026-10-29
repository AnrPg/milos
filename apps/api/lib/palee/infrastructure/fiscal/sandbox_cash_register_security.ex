defmodule Palee.Infrastructure.Fiscal.SandboxCashRegisterSecurity do
  @moduledoc """
  A TSE, an RKSV signature creation unit and fiskaly SIGN FR that are not
  there (ADR-251, ADR-266):
  every receipt is "signed" without the network. Used by the `sandbox`
  environment (pilots before a business has a fiskaly account, demos,
  development) and by tests.

  Serial numbers start with `SANDBOX`, signatures are an HMAC of the
  receipt that no tax office will accept, and the same external id always
  gets the same transaction, so a read-back finds what was signed.
  """

  @behaviour Palee.Fiscal.Ports.CashRegisterSecurity

  alias Palee.Fiscal.Domain.RksvReceipt

  @impl true
  def provision(connection, _context) do
    start =
      if connection.device == "rksv",
        do:
          signature(connection, %{
            external_id: connection.register_id,
            kind: "start",
            schema: RksvReceipt.null_schema()
          })

    {{:ok,
      %{
        unit_serial: "SANDBOX-" <> short(connection.unit_id),
        register_serial: "SANDBOX-" <> short(connection.register_id),
        public_key: Base.encode64("sandbox-public-key"),
        admin_pin: nil,
        start: start
      }}, wire(nil)}
  end

  @impl true
  def sign(connection, request),
    do: {{:ok, signature(connection, request)}, wire(Jason.encode!(request.schema))}

  @impl true
  def lookup(connection, request), do: {{:ok, signature(connection, request)}, wire(nil)}

  defp signature(connection, request) do
    digest =
      :crypto.mac(
        :hmac,
        :sha256,
        "palee-sandbox",
        "#{request.external_id}:#{Jason.encode!(request.schema)}"
      )

    <<number::unsigned-integer-size(32), counter::unsigned-integer-size(32), _rest::binary>> =
      digest

    now = DateTime.utc_now()
    value = Base.encode64(digest)
    unit_serial = "SANDBOX-" <> short(connection.unit_id)
    register_serial = "SANDBOX-" <> short(connection.register_id)

    base = %{
      transaction_number: rem(number, 1_000_000) + 1,
      signature_counter: rem(counter, 1_000_000) + 1,
      signature_value: value,
      signature_algorithm: "ecdsa-plain-SHA256",
      time_format: "unixTime",
      started_at_device: now,
      finished_at_device: now,
      unit_serial: unit_serial,
      register_serial: register_serial,
      device_failed: false,
      hint: nil
    }

    case connection.device do
      "tse" ->
        Map.merge(base, %{
          receipt_number: nil,
          qr_code_data:
            Enum.join(
              [
                "V0",
                register_serial,
                "Kassenbeleg-V1",
                "Beleg^sandbox",
                base.transaction_number,
                base.signature_counter,
                DateTime.to_iso8601(now),
                DateTime.to_iso8601(now),
                base.signature_algorithm,
                base.time_format,
                value,
                Base.encode64("sandbox-public-key")
              ],
              ";"
            )
        })

      "rksv" ->
        number = Integer.to_string(base.transaction_number)
        amounts = rksv_amounts(request.schema)

        Map.merge(base, %{
          receipt_number: number,
          qr_code_data:
            Enum.join(
              [
                "",
                "R1-AT1",
                register_serial,
                number,
                now
                |> DateTime.truncate(:second)
                |> DateTime.to_naive()
                |> NaiveDateTime.to_iso8601()
              ] ++
                amounts ++ [Base.encode64("sandbox"), "SANDBOX", Base.encode64("previous"), value],
              "_"
            )
        })

      # France (ADR-266): a record id stands in for fiskaly's.
      "sign_fr" ->
        Map.merge(base, %{receipt_number: "sandbox-" <> to_string(request.external_id), qr_code_data: nil})
    end
  end

  defp rksv_amounts(schema) do
    rates =
      schema
      |> get_in(["standard_v1", "receipt", "amounts_per_vat_rate"])
      |> List.wrap()
      |> Map.new(&{&1["vat_rate"], &1["amount"]})

    Enum.map(["STANDARD", "REDUCED_1", "REDUCED_2", "ZERO", "SPECIAL"], fn rate ->
      rates |> Map.get(rate, "0.00") |> String.replace(".", ",")
    end)
  end

  defp short(id), do: id |> to_string() |> String.replace("-", "") |> String.slice(0, 12)

  defp wire(body), do: %{request_body: body, response_status: nil, response_body: nil}
end
