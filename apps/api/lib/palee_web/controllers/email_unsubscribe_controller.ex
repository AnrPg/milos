defmodule PaleeWeb.EmailUnsubscribeController do
  @moduledoc """
  The one-click unsubscribe link of transactional email (ADR-212).

    * `POST /api/email/unsubscribe/:token` unsubscribes: a mail app's
      one-click request (RFC 8058, body `List-Unsubscribe=One-Click`) or
      the button of the page below.
    * `GET` only shows a page with that button, so a link scanner that
      opens every link unsubscribes nobody.

  The token is signed and names the address only by its digest. A small
  self-contained page in the email's language: no scripts, no external
  resources, not frameable. Not part of the app's OpenAPI contract.
  """

  use PaleeWeb, :controller

  alias Palee.BrandPalette
  alias Palee.Email.Layout

  @csp "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; " <>
         "frame-ancestors 'none'"

  def show(conn, %{"token" => token}) do
    case Palee.Email.unsubscribe_info(token) do
      {:ok, %{locale: locale}} -> page(conn, 200, locale, :confirm, token)
      {:error, :invalid} -> page(conn, 404, "en", :invalid, token)
    end
  end

  def create(conn, %{"token" => token}) do
    case Palee.Email.unsubscribe(token) do
      {:ok, %{locale: locale}} -> page(conn, 200, locale, :done, token)
      {:error, :invalid} -> page(conn, 404, "en", :invalid, token)
    end
  end

  defp page(conn, status, locale, state, token) do
    conn
    |> put_resp_content_type("text/html", "utf-8")
    |> put_resp_header("content-security-policy", @csp)
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_resp(status, html(locale, state, token))
  end

  defp html(locale, state, token) do
    product = Layout.product_name()

    explain =
      t(
        locale,
        "You will no longer receive this kind of email from %{product}. Emails about your account and its security still arrive.",
        product: product
      )

    {heading, body} =
      case state do
        :confirm ->
          {t(locale, "Unsubscribe from these emails"),
           """
           <p>#{Layout.escape(explain)}</p>
           <form method="post" action="/api/email/unsubscribe/#{Layout.escape(token)}">
           <input type="hidden" name="List-Unsubscribe" value="One-Click">
           <button type="submit" style="#{button_style()}">#{Layout.escape(t(locale, "Unsubscribe from these emails"))}</button>
           </form>
           """}

        :done ->
          {t(locale, "You're unsubscribed"), "<p>#{Layout.escape(explain)}</p>"}

        :invalid ->
          {t(locale, "This unsubscribe link is not valid."), ""}
      end

    dir = if Layout.rtl?(locale), do: "rtl", else: "ltr"

    """
    <!DOCTYPE html>
    <html lang="#{Layout.escape(String.replace(locale, "_", "-"))}" dir="#{dir}">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>#{Layout.escape(product)}</title>
    </head>
    <body style="margin:0;padding:24px 16px;background:#{c(:bg)};color:#{c(:text)};font-family:-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;font-size:15px;line-height:1.55;">
    <main style="max-width:480px;margin:0 auto;background:#{c(:paper)};border:1px solid #{c(:border)};border-radius:12px;padding:24px;">
    <p style="margin:0 0 8px;font-weight:700;color:#{c(:deep)};">#{Layout.escape(product)}</p>
    <h1 style="margin:0 0 12px;font-size:20px;color:#{c(:deep)};">#{Layout.escape(heading)}</h1>
    #{body}
    </main>
    </body>
    </html>
    """
  end

  defp button_style,
    do:
      "border:0;border-radius:8px;padding:12px 22px;font-weight:600;font-size:15px;cursor:pointer;" <>
        "background:#{c(:primary)};color:#{c(:primary_contrast)};"

  defp t(locale, message, bindings \\ []), do: Layout.t(locale, message, Map.new(bindings))

  defp c(token), do: BrandPalette.colour(token)
end
