defmodule Palee.Infrastructure.Fiscal.MyData.XmlCodec do
  @moduledoc """
  Writes myDATA `InvoicesDoc` XML from the element trees of
  `Fiscal.Domain.MyDataInvoice` and reads AADE's `ResponseDoc` (ADR-243,
  schemas in `priv/fiscal/mydata/v2.0.1`).

  Element names are strings (invoice namespace, the default) or
  `{:icls, name}` (income classification namespace). Text is escaped;
  responses are parsed with entities disabled (no XXE, no entity
  expansion) and read by local name, so a namespace prefix change does not
  break them.
  """

  @invoice_ns "http://www.aade.gr/myDATA/invoice/v1.0"
  @icls_ns "https://www.aade.gr/myDATA/incomeClassificaton/v1.0"
  @max_response_bytes 1_000_000

  @doc "One `InvoicesDoc` with the given invoices."
  def invoices_doc(invoices) when is_list(invoices) do
    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="UTF-8"?>),
      ~s(<InvoicesDoc xmlns="#{@invoice_ns}" xmlns:icls="#{@icls_ns}">),
      Enum.map(invoices, &element({"invoice", &1})),
      "</InvoicesDoc>"
    ])
  end

  defp element({name, children}) when is_list(children) do
    tag = tag(name)
    ["<", tag, ">", Enum.map(children, &element/1), "</", tag, ">"]
  end

  defp element({name, value}) when is_binary(value) do
    tag = tag(name)
    ["<", tag, ">", escape(value), "</", tag, ">"]
  end

  defp tag({:icls, name}), do: "icls:" <> name
  defp tag(name) when is_binary(name), do: name

  @doc "XML text escaping."
  def escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  @doc """
  The `response` entries of a `ResponseDoc`:
  `[%{index, status, uid, mark, authentication_code, qr_url, errors}]`, or
  `{:error, :invalid_response}`.
  """
  def parse_response(body) when is_binary(body) and byte_size(body) <= @max_response_bytes do
    {document, _rest} =
      body
      |> :binary.bin_to_list()
      |> :xmerl_scan.string(allow_entities: false, quiet: true, fetch_fun: &no_fetch/2)

    responses =
      document
      |> xpath("//*[local-name()='response']")
      |> Enum.map(fn response ->
        %{
          index: text(response, "index"),
          status: text(response, "statusCode"),
          uid: text(response, "invoiceUid"),
          mark: text(response, "invoiceMark"),
          authentication_code: text(response, "authenticationCode"),
          qr_url: text(response, "qrUrl"),
          errors:
            response
            |> xpath("./*[local-name()='errors']/*[local-name()='error']")
            |> Enum.map(&%{code: text(&1, "code"), message: text(&1, "message")})
        }
      end)

    {:ok, responses}
  catch
    _kind, _reason -> {:error, :invalid_response}
  end

  def parse_response(_body), do: {:error, :invalid_response}

  defp no_fetch(_uri, _state), do: {:error, :external_entities_disabled}

  defp xpath(node, path), do: :xmerl_xpath.string(String.to_charlist(path), node)

  defp text(node, name) do
    case xpath(node, "./*[local-name()='#{name}']/text()") do
      [] ->
        nil

      texts ->
        texts
        |> Enum.map(fn {:xmlText, _parents, _pos, _lang, value, _type} -> value end)
        |> IO.chardata_to_string()
        |> String.trim()
    end
  end
end
