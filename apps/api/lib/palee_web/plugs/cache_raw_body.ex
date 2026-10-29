defmodule PaleeWeb.Plugs.CacheRawBody do
  @moduledoc """
  ADR-246: keeps the exact request body of payment-provider webhooks, whose
  signatures cover the raw bytes (Stripe). Only for
  `/api/webhooks/payments/…`; every other request is read as before.
  """

  @prefix "/api/webhooks/payments/"

  def read_body(%Plug.Conn{request_path: @prefix <> _rest} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, update_in(conn.assigns[:raw_body], &[body | &1 || []])}

      {:more, body, conn} ->
        {:more, body, update_in(conn.assigns[:raw_body], &[body | &1 || []])}

      other ->
        other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)

  @doc "The raw body cached for this request (\"\" when none)."
  def raw_body(conn) do
    case conn.assigns[:raw_body] do
      nil -> ""
      chunks -> chunks |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end
end
