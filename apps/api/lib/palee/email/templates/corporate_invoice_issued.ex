defmodule Palee.Email.Templates.CorporateInvoiceIssued do
  @moduledoc """
  `:corporate_invoice_issued` (ADR-098, ADR-203): the email a corporate
  client's billing contact gets when an invoice is issued. Rendered by
  `Palee.Finance.Emails.CorporateInvoiceEmail` in the gym's default locale.

  Assigns: `invoice`, `client` (with `company_name`, `contact_name`),
  `gym_name`.
  """

  use Palee.Email.Template, category: :transactional

  alias Palee.Finance.Emails.CorporateInvoiceEmail

  @impl true
  def subject(assigns, locale), do: CorporateInvoiceEmail.render(:issued, assigns, locale).subject

  @impl true
  def text(assigns, locale), do: CorporateInvoiceEmail.render(:issued, assigns, locale).text

  @impl true
  def html(assigns, locale), do: CorporateInvoiceEmail.render(:issued, assigns, locale).html
end
