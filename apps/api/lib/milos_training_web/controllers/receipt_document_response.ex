defmodule MilosTrainingWeb.Controllers.ReceiptDocumentResponse do
  @moduledoc """
  Shared HTTP handling for the ADR-126 printable refund receipt: locale
  resolution and a locked-down HTML response (no scripts, no external
  resources, not frameable, never cached by shared caches).
  """

  import Plug.Conn

  alias MilosTraining.Identity

  @csp "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; " <>
         "frame-ancestors 'none'"

  @doc "Requested `locale` if supported, else the viewer's preference, else English."
  def locale(conn, params) do
    supported = Identity.supported_locales()

    cond do
      params["locale"] in supported ->
        params["locale"]

      (preferred = viewer_locale(conn)) in supported ->
        preferred

      true ->
        "en"
    end
  end

  def send(conn, %{html: html, receipt_number: receipt_number}) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("content-security-policy", @csp)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "private, no-store")
    |> put_resp_header("content-disposition", ~s(inline; filename="#{safe(receipt_number)}.html"))
    |> send_resp(200, html)
  end

  defp viewer_locale(conn) do
    case Guardian.Plug.current_resource(conn) do
      %{preferred_locale: locale} -> locale
      _ -> nil
    end
  end

  defp safe(value), do: String.replace(to_string(value), ~r/[^A-Za-z0-9_-]/, "")
end
