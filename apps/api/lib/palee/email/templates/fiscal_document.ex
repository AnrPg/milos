defmodule Palee.Email.Templates.FiscalDocument do
  @moduledoc """
  `:fiscal_document` (ADR-265): «Αποστολή με email» of a fiscal document
  (receipt, invoice, credit note). The PDF goes as an attachment; the email
  only names the document. Rendered in the document's language.

  Category `:transactional`: a demo business cannot send it (ADR-184).

  Assigns: `business` (the seller's name as printed), `title` (the
  document's printed title, e.g. «Απόδειξη Παροχής Υπηρεσιών»), `number`,
  `issue_date` and `total` (both already formatted for the language).
  Strings: the `emails` gettext domain.
  """

  use Palee.Email.Template, category: :transactional

  # Staff may resend a document, but one address never gets a flood.
  @impl true
  def throttle, do: %{max_per_day: 10, min_interval_seconds: 30}

  @impl true
  def subject(assigns, locale),
    do:
      t(locale, "%{title} %{number} from %{business}", %{
        title: assigns.title,
        number: assigns.number,
        business: assigns.business
      })

  @impl true
  def text(assigns, locale) do
    Layout.text(
      locale,
      [intro(assigns, locale), Layout.text_details(details(assigns, locale)), note(locale)],
      reason: Layout.reason(locale, {:business, assigns.business})
    )
  end

  @impl true
  def html(assigns, locale) do
    Layout.html(
      locale,
      [
        Layout.heading(subject(assigns, locale)),
        Layout.paragraph(intro(assigns, locale)),
        Layout.details(details(assigns, locale)),
        Layout.note(note(locale))
      ],
      reason: Layout.reason(locale, {:business, assigns.business}),
      preheader: intro(assigns, locale)
    )
  end

  defp intro(assigns, locale),
    do:
      t(locale, "%{business} sent you this document. You'll find it attached as a PDF.", %{
        business: assigns.business
      })

  defp details(assigns, locale) do
    [
      {t(locale, "Document"), "#{assigns.title} #{assigns.number}"},
      {t(locale, "Date of issue"), assigns.issue_date},
      {t(locale, "Total"), assigns.total}
    ]
  end

  defp note(locale),
    do: t(locale, "Keep it for your records. For questions about it, contact the business.")
end
