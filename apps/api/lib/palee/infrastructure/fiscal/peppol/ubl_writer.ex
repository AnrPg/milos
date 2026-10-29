defmodule Palee.Infrastructure.Fiscal.Peppol.UblWriter do
  @moduledoc """
  Writes the element trees of `Fiscal.Domain.UblInvoice` as UBL 2.1 XML
  (ADR-250; schemas in `priv/fiscal/ubl/2.1`). Text and attribute values
  are escaped; the output is UTF-8 without a byte order mark.
  """

  @namespaces %{
    "Invoice" => "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2",
    "CreditNote" => "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
  }
  @cac "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
  @cbc "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"

  @doc "The XML document of `{root, children}` (`root` is `Invoice` or `CreditNote`)."
  def write({root, children}) when is_map_key(@namespaces, root) do
    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<#{root} xmlns="#{Map.fetch!(@namespaces, root)}" xmlns:cac="#{@cac}" xmlns:cbc="#{@cbc}">),
      Enum.map(children, &element/1),
      "</#{root}>"
    ])
  end

  defp element({name, attributes, text}) when is_list(attributes) and is_binary(text) do
    ["<", name, attrs(attributes), ">", escape(text), "</", name, ">"]
  end

  defp element({name, children}) when is_list(children) do
    ["<", name, ">", Enum.map(children, &element/1), "</", name, ">"]
  end

  defp element({name, text}) when is_binary(text) do
    ["<", name, ">", escape(text), "</", name, ">"]
  end

  defp attrs(attributes) do
    Enum.map(attributes, fn {key, value} -> [" ", Atom.to_string(key), "=\"", escape(value), "\""] end)
  end

  @doc "XML text escaping."
  def escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
