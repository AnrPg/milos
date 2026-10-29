defmodule Palee.Fiscal.Ports.BusinessRegistry do
  @moduledoc """
  Looks up a business in its tax authority's registry by tax ID (ADR-265):
  «Συμπλήρωση από το ΑΦΜ». One adapter per connection environment:
  `Sandbox` (no network: pilots, demos and tests) and `AadeRegistry`
  (AADE's RgWsPublic2 SOAP service, with the business's own special
  credentials).

  `connection` holds the decrypted credentials
  (`%{environment, user_id, subscription_key}`: the AADE username and
  password); adapters never log them.

  A found business:

      %{tax_id, legal_name, trade_name, tax_office, tax_office_code,
        street, building_number, postal_code, city, activity_code,
        activity_description, activities: [%{code, description, main}],
        active, legal_status, vat_registered}

  Errors: `:not_found` (no such or invalid tax ID at the authority),
  `:credentials_rejected`, `:limit_reached` (the authority's call quota),
  `:unavailable` (network, timeout, technical error).
  """

  @type connection :: %{
          required(:environment) => String.t(),
          optional(:user_id) => String.t() | nil,
          optional(:subscription_key) => String.t() | nil
        }

  @type activity :: %{code: String.t(), description: String.t() | nil, main: boolean()}

  @type business :: %{
          tax_id: String.t(),
          legal_name: String.t() | nil,
          trade_name: String.t() | nil,
          tax_office: String.t() | nil,
          tax_office_code: String.t() | nil,
          street: String.t() | nil,
          building_number: String.t() | nil,
          postal_code: String.t() | nil,
          city: String.t() | nil,
          activity_code: String.t() | nil,
          activity_description: String.t() | nil,
          activities: [activity()],
          active: boolean(),
          legal_status: String.t() | nil,
          vat_registered: boolean()
        }

  @callback lookup(connection(), tax_id :: String.t(), as_on :: Date.t()) ::
              {:ok, business()}
              | {:error, :not_found | :credentials_rejected | :limit_reached | :unavailable}
end
