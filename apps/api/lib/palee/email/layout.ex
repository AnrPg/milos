defmodule Palee.Email.Layout do
  @moduledoc """
  The shared look of every Palee email (ADR-203): an HTML document and its
  plain-text twin, in the Palee theme colours (`BrandPalette`), with the
  product name from the `mail_from` config, and a footer that says why the
  reader gets the email.

  Templates build their content from the components here and pass it to
  `html/3` and `text/3`. HTML components escape every value they are given,
  so a template never interpolates raw input into HTML. Strings come from
  the `emails` gettext domain through `t/3`; Arabic and Hebrew emails are
  laid out right to left.

  Options of `html/3` and `text/3`:

    * `:reason` - the footer's "you get this because ..." sentence, already
      translated (`reason/3` builds the common ones). Defaults to the
      account one.
    * `:preheader` - the preview line mail apps show after the subject
      (HTML only).
  """

  alias Palee.Application.PublicURL
  alias Palee.BrandPalette
  alias Palee.Localization

  @domain "emails"
  @rtl_locales ~w(ar he)
  @font "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

  # -- strings -----------------------------------------------------------------

  @doc "A string of the `emails` gettext domain in `locale`."
  def t(locale, message, bindings \\ %{}),
    do: Localization.translate(locale, message, Map.new(bindings), @domain)

  @doc "The product name emails are signed with (`MAIL_FROM_NAME`)."
  def product_name, do: :palee |> Application.fetch_env!(:mail_from) |> Keyword.fetch!(:name)

  @doc """
  A footer reason: `:account` (the reader has a Palee account) or
  `{:business, name}` (a business sent it through Palee).
  """
  def reason(locale, :account),
    do:
      t(locale, "You're receiving this email because you have a %{product} account.", %{
        product: product_name()
      })

  def reason(locale, {:business, name}),
    do:
      t(locale, "You're receiving this email because %{business} sent it to you through %{product}.", %{
        business: name,
        product: product_name()
      })

  @doc "Whether `locale` is written right to left."
  def rtl?(locale), do: locale in @rtl_locales

  # -- documents ---------------------------------------------------------------

  @doc "The HTML document around `blocks` (components of this module, or escaped HTML)."
  def html(locale, blocks, opts \\ []) do
    dir = if rtl?(locale), do: "rtl", else: "ltr"
    align = if rtl?(locale), do: "right", else: "left"
    reason = Keyword.get_lazy(opts, :reason, fn -> reason(locale, :account) end)
    preheader = Keyword.get(opts, :preheader)
    base_url = PublicURL.base_url()

    """
    <!DOCTYPE html>
    <html lang="#{escape(lang(locale))}" dir="#{dir}">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light">
    <meta name="supported-color-schemes" content="light">
    </head>
    <body style="margin:0;padding:0;background:#{c(:bg)};">
    #{preheader_html(preheader)}<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#{c(:bg)};">
    <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" dir="#{dir}" style="max-width:560px;background:#{c(:paper)};border:1px solid #{c(:border)};border-radius:12px;">
    <tr><td style="padding:24px 28px 0;font-family:#{@font};font-size:18px;font-weight:700;color:#{c(:deep)};text-align:#{align};">#{escape(product_name())}</td></tr>
    <tr><td style="padding:12px 28px 28px;font-family:#{@font};font-size:15px;line-height:1.55;color:#{c(:text)};text-align:#{align};">
    #{IO.iodata_to_binary(blocks)}
    </td></tr>
    </table>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" dir="#{dir}" style="max-width:560px;">
    <tr><td style="padding:16px 28px;font-family:#{@font};font-size:12px;line-height:1.5;color:#{c(:muted)};text-align:#{align};">
    #{escape(reason)}<br>
    #{escape(t(locale, "This email was sent automatically by %{product}.", %{product: product_name()}))} <a href="#{escape(base_url)}" style="color:#{c(:muted)};">#{escape(host(base_url))}</a>
    </td></tr>
    </table>
    </td></tr>
    </table>
    </body>
    </html>
    """
  end

  @doc "The plain-text twin of `html/3`: `blocks` are strings, one paragraph each."
  def text(locale, blocks, opts \\ []) do
    reason = Keyword.get_lazy(opts, :reason, fn -> reason(locale, :account) end)
    base_url = PublicURL.base_url()

    footer = [
      reason,
      t(locale, "This email was sent automatically by %{product}.", %{product: product_name()}) <>
        " " <> base_url
    ]

    Enum.join(List.flatten(blocks) |> Enum.reject(&(&1 in [nil, ""])), "\n\n") <>
      "\n\n-- \n" <> Enum.join(footer, "\n") <> "\n"
  end

  # -- HTML components ---------------------------------------------------------

  @doc "A paragraph."
  def paragraph(text),
    do: ~s(<p style="margin:0 0 14px;">#{escape(text)}</p>\n)

  @doc "A heading at the top of the content."
  def heading(text),
    do:
      ~s(<h1 style="margin:8px 0 16px;font-size:20px;line-height:1.3;color:#{c(:deep)};">#{escape(text)}</h1>\n)

  @doc "Small print under the content (lifetimes, \"if this wasn't you\")."
  def note(text),
    do: ~s(<p style="margin:16px 0 0;font-size:13px;color:#{c(:text_soft)};">#{escape(text)}</p>\n)

  @doc "The call to action: a button linking to `url`."
  def button(label, url) do
    ~s(<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:24px 0;"><tr>) <>
      ~s(<td style="border-radius:8px;background:#{c(:primary)};">) <>
      ~s(<a href="#{escape(url)}" style="display:inline-block;padding:12px 22px;font-weight:600;) <>
      ~s(color:#{c(:primary_contrast)};text-decoration:none;border-radius:8px;">#{escape(label)}</a>) <>
      "</td></tr></table>\n"
  end

  @doc "The link spelled out, for when the button does not work."
  def fallback_link(locale, url) do
    ~s(<p style="margin:16px 0 0;font-size:12px;color:#{c(:muted)};">) <>
      escape(t(locale, "If the button doesn't work, copy this link into your browser:")) <>
      ~s(<br><a href="#{escape(url)}" style="color:#{c(:muted)};word-break:break-all;">#{escape(url)}</a></p>\n)
  end

  @doc "Label and value rows (an invoice's details)."
  def details(rows) do
    body =
      Enum.map_join(rows, "", fn {label, value} ->
        ~s(<tr><td style="padding:4px 12px 4px 0;color:#{c(:muted)};">#{escape(label)}</td>) <>
          ~s(<td style="padding:4px 0;font-weight:600;">#{escape(value)}</td></tr>)
      end)

    ~s(<table role="presentation" style="border-collapse:collapse;margin:16px 0;">#{body}</table>\n)
  end

  @doc "A code the reader may type by hand."
  def code(value),
    do:
      ~s(<p style="margin:16px 0;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:16px;) <>
        ~s(letter-spacing:1px;padding:10px 14px;background:#{c(:bg)};border-radius:8px;display:inline-block;">) <>
        escape(value) <> "</p>\n"

  # -- text components ---------------------------------------------------------

  @doc "The text twin of `button/2`."
  def text_button(label, url), do: "#{label}:\n#{url}"

  @doc "The text twin of `details/1`."
  def text_details(rows), do: Enum.map_join(rows, "\n", fn {label, value} -> "#{label}: #{value}" end)

  # -- helpers -----------------------------------------------------------------

  @doc "HTML-escapes a value (anything `to_string/1` takes)."
  def escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp preheader_html(nil), do: ""

  defp preheader_html(text),
    do:
      ~s(<div style="display:none;max-height:0;overflow:hidden;opacity:0;">#{escape(text)}</div>\n)

  defp lang(locale), do: String.replace(locale || "en", "_", "-")

  defp host(url), do: URI.parse(url).host || url

  defp c(token), do: BrandPalette.colour(token)
end
