defmodule MilosTraining.Finance.Domain.RefundReceiptDocument do
  @moduledoc """
  Deterministic, printable HTML rendering of a refund receipt snapshot
  (ADR-116). There is no PDF library in the stack, so the receipt document is
  a self-contained HTML page (inline print stylesheet, no scripts, no
  external resources) that browsers print or save as PDF.

  The same `(snapshot, labels, opts)` always renders the same bytes: only the
  immutable snapshot and the caller-supplied translated labels are used, and
  every interpolated value is HTML-escaped.
  """

  @label_keys [
    :title,
    :receipt_number,
    :issued_on,
    :issued_by,
    :issued_to,
    :refund_details,
    :refund_type,
    :refunded_amount,
    :reason,
    :original_payment,
    :payment_date,
    :payment_method,
    :original_amount,
    :invoice,
    :previously_refunded,
    :remaining_paid,
    :type_refund,
    :type_payment_reversal,
    :immutable_notice,
    :fingerprint,
    :not_provided
  ]

  @doc "Label keys a caller must translate."
  def label_keys, do: @label_keys

  @doc """
  Renders the receipt. `labels` maps every `label_keys/0` key to text;
  `opts` accepts `:lang` (BCP 47 tag, default `"en"`), `:dir` (`"ltr"` or
  `"rtl"`) and `:fingerprint` (the stored SHA-256).
  """
  def render_html(snapshot, labels, opts \\ []) when is_map(snapshot) and is_map(labels) do
    lang = Keyword.get(opts, :lang, "en")
    dir = if Keyword.get(opts, :dir) == "rtl", do: "rtl", else: "ltr"
    fingerprint = Keyword.get(opts, :fingerprint)
    reversal = snapshot["reversal"] || %{}
    payment = snapshot["original_payment"] || %{}
    totals = snapshot["totals"] || %{}
    invoice = snapshot["invoice"]
    currency = reversal["currency"] || payment["currency"] || "EUR"
    label = &label(labels, &1)
    missing = label.(:not_provided)

    IO.iodata_to_binary([
      "<!DOCTYPE html>\n",
      "<html lang=\"",
      escape(lang),
      "\" dir=\"",
      dir,
      "\">\n<head>\n<meta charset=\"utf-8\">\n",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
      "<title>",
      escape(label.(:title)),
      " ",
      escape(snapshot["receipt_number"]),
      "</title>\n<style>",
      stylesheet(),
      "</style>\n</head>\n<body>\n<main class=\"receipt\">\n",
      "<header>\n<h1>",
      escape(label.(:title)),
      "</h1>\n<p class=\"number\">",
      escape(label.(:receipt_number)),
      ": <strong>",
      escape(snapshot["receipt_number"]),
      "</strong></p>\n</header>\n",
      "<dl class=\"parties\">\n",
      row(label.(:issued_on), date_part(snapshot["issued_at"]), missing),
      row(label.(:issued_by), get_in(snapshot, ["organization", "name"]), missing),
      row(label.(:issued_to), get_in(snapshot, ["member", "display_name"]), missing),
      "</dl>\n<section>\n<h2>",
      escape(label.(:refund_details)),
      "</h2>\n<dl>\n",
      row(label.(:refund_type), type_label(reversal["type"], labels), missing),
      row(
        label.(:refunded_amount),
        money(totals["refunded_cents"] || reversal["amount_cents"], currency),
        missing
      ),
      row(label.(:reason), reversal["reason"], missing),
      "</dl>\n</section>\n<section>\n<h2>",
      escape(label.(:original_payment)),
      "</h2>\n<dl>\n",
      row(label.(:payment_date), payment["paid_on"], missing),
      row(label.(:payment_method), payment["payment_method"], missing),
      row(
        label.(:original_amount),
        money(payment["amount_cents"], payment["currency"] || currency),
        missing
      ),
      row(label.(:invoice), invoice && invoice["invoice_number"], missing),
      row(
        label.(:previously_refunded),
        money(totals["previously_refunded_cents"], currency),
        missing
      ),
      row(label.(:remaining_paid), money(totals["remaining_paid_cents"], currency), missing),
      "</dl>\n</section>\n<footer>\n<p>",
      escape(label.(:immutable_notice)),
      "</p>\n",
      fingerprint_line(label.(:fingerprint), fingerprint),
      "</footer>\n</main>\n</body>\n</html>\n"
    ])
  end

  @doc "Formats integer cents as `12.50 EUR` (locale-neutral, deterministic)."
  def money(nil, _currency), do: nil

  def money(cents, currency) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    absolute = abs(cents)

    fraction =
      absolute |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")

    "#{sign}#{div(absolute, 100)}.#{fraction} #{currency || "EUR"}"
  end

  @doc "Escapes the five HTML-significant characters."
  def escape(nil), do: ""

  def escape(value) when is_binary(value) do
    for <<char <- value>>, into: "" do
      case char do
        ?& -> "&amp;"
        ?< -> "&lt;"
        ?> -> "&gt;"
        ?" -> "&quot;"
        ?' -> "&#39;"
        other -> <<other>>
      end
    end
  end

  def escape(value), do: value |> to_string() |> escape()

  defp row(term, value, missing) do
    shown = if value in [nil, ""], do: missing, else: value
    ["<dt>", escape(term), "</dt><dd>", escape(shown), "</dd>\n"]
  end

  defp fingerprint_line(_label, nil), do: []

  defp fingerprint_line(label, fingerprint),
    do: [
      "<p class=\"fingerprint\">",
      escape(label),
      ": <code>",
      escape(fingerprint),
      "</code></p>\n"
    ]

  defp type_label("refund", labels), do: label(labels, :type_refund)
  defp type_label("payment_reversal", labels), do: label(labels, :type_payment_reversal)
  defp type_label(other, _labels), do: other

  defp date_part(nil), do: nil
  defp date_part(value) when is_binary(value), do: String.slice(value, 0, 10)

  defp label(labels, key), do: Map.get(labels, key) || Atom.to_string(key)

  defp stylesheet do
    "body{margin:0;background:#f4f4f5;color:#18181b;font:15px/1.5 system-ui,-apple-system," <>
      "\"Segoe UI\",Roboto,sans-serif}.receipt{max-width:720px;margin:32px auto;background:#fff;" <>
      "padding:40px;border:1px solid #e4e4e7;border-radius:12px}header{border-bottom:2px solid " <>
      "#18181b;margin-bottom:24px}h1{margin:0 0 4px;font-size:26px}h2{font-size:15px;" <>
      "text-transform:uppercase;letter-spacing:.08em;color:#52525b;margin:24px 0 8px}" <>
      ".number{margin:0 0 16px}dl{display:grid;grid-template-columns:minmax(160px,1fr) 2fr;" <>
      "gap:6px 16px;margin:0}dt{color:#52525b}dd{margin:0;font-weight:600;overflow-wrap:anywhere}" <>
      "footer{margin-top:32px;border-top:1px solid #e4e4e7;padding-top:16px;font-size:12px;" <>
      "color:#52525b}code{font-size:11px;overflow-wrap:anywhere}@media print{body{background:#fff}" <>
      ".receipt{margin:0;border:0;border-radius:0;max-width:none;padding:0}}"
  end
end
