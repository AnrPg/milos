defmodule Palee.Email.Templates.CorporateInvoiceReminder do
  @moduledoc """
  `:corporate_invoice_reminder` (ADR-098, ADR-203): the email a corporate
  client's billing contact gets while an invoice is overdue. Rendered by
  `Palee.Finance.Emails.CorporateInvoiceEmail` in the gym's default locale.

  Assigns: `invoice`, `client` (with `company_name`, `contact_name`),
  `gym_name`.
  """

  use Palee.Email.Template, category: :transactional

  alias Palee.Finance.Emails.CorporateInvoiceEmail

  @impl true
  def subject(assigns, locale),
    do: CorporateInvoiceEmail.render(:reminder, assigns, locale).subject

  @impl true
  def text(assigns, locale), do: CorporateInvoiceEmail.render(:reminder, assigns, locale).text

  @impl true
  def html(assigns, locale), do: CorporateInvoiceEmail.render(:reminder, assigns, locale).html
end
