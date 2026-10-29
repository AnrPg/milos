defmodule Palee.Infrastructure.Fiscal.SandboxAuthorityGateway do
  @moduledoc """
  An authority that is not there (ADR-243): accepts every well-formed
  document with a made-up MARK, without the network. Used by the
  `sandbox` environment (pilots before a gym has myDATA credentials,
  demos, development) and by tests.

  Sandbox MARKs start with `9000` so they can never be mistaken for real
  ones, and the same document always gets the same MARK.
  """

  @behaviour Palee.Fiscal.Ports.AuthorityGateway

  alias Palee.Infrastructure.Fiscal.MyData.XmlCodec

  @impl true
  def submit(_connection, invoice) do
    body = XmlCodec.invoices_doc([invoice])
    digest = :crypto.hash(:sha, body)

    result =
      if Enum.any?(invoice, &match?({"invoiceDetails", _}, &1)) do
        <<number::unsigned-integer-size(40), _rest::binary>> = digest

        {:ok,
         %{
           mark:
             "9000" <>
               (number
                |> rem(100_000_000_000)
                |> Integer.to_string()
                |> String.pad_leading(11, "0")),
           uid: Base.encode16(digest),
           authentication_code: nil,
           qr_url: nil
         }}
      else
        {:error, {:rejected, [%{code: "sandbox", message: "Document without lines"}]}}
      end

    {result, %{request_body: body, response_status: nil, response_body: nil}}
  end
end
