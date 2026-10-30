defmodule Palee.Repo.Migrations.FiskalyEinvoiceAndSignFr do
  @moduledoc """
  fiskaly as the single fiscal vendor outside Greece (ADR-250 update,
  ADR-266).

    * `fiscal_network_connections`: provider `fiskaly` (fiskaly
      E-INVOICE) next to `sandbox` and the retired `storecove` (kept
      allowed so old rows stay valid); an encrypted `api_secret` (fiskaly
      authenticates with a key and a secret). A fiskaly connection may
      carry no credentials of its own: it then uses the business's fiskaly
      till connection (one fiskaly account per business).
    * `fiscal_till_connections` / `fiscal_till_signatures`: device
      `sign_fr` (France, fiskaly SIGN FR) next to `tse` and `rksv`.
  """

  use Ecto.Migration

  def up do
    alter table(:fiscal_network_connections) do
      add :api_secret, :binary
    end

    drop constraint(:fiscal_network_connections, :fiscal_network_connections_check)

    create constraint(:fiscal_network_connections, :fiscal_network_connections_check,
             check: """
             network IN ('peppol') AND provider IN ('sandbox', 'storecove', 'fiskaly')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR legal_entity_id IS NOT NULL)
             AND (provider <> 'storecove' OR api_key IS NOT NULL)
             AND ((api_key IS NULL) = (api_secret IS NULL) OR provider = 'storecove')
             """
           )

    drop constraint(:fiscal_till_connections, :fiscal_till_connections_check)

    create constraint(:fiscal_till_connections, :fiscal_till_connections_check,
             check: """
             device IN ('tse', 'rksv', 'sign_fr') AND provider IN ('sandbox', 'fiskaly')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('provisioning', 'active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR (api_key IS NOT NULL AND api_secret IS NOT NULL))
             AND (status <> 'active' OR provisioned_at IS NOT NULL)
             """
           )

    drop constraint(:fiscal_till_signatures, :fiscal_till_signatures_check)

    create constraint(:fiscal_till_signatures, :fiscal_till_signatures_check,
             check: """
             device IN ('tse', 'rksv', 'sign_fr')
             AND kind IN ('receipt', 'start', 'null', 'monthly', 'yearly', 'closing')
             AND status IN ('pending', 'sending', 'signed', 'uncertain', 'device_failed',
                            'rejected', 'failed')
             AND attempts >= 0
             AND (kind = 'receipt') = (document_id IS NOT NULL)
             AND (kind <> 'receipt' OR period IS NULL)
             AND (status <> 'signed' OR signature_value IS NOT NULL)
             AND (status <> 'device_failed' OR failed_at IS NOT NULL)
             """
           )
  end

  def down do
    execute("DELETE FROM fiscal_till_signatures WHERE device = 'sign_fr'")
    execute("DELETE FROM fiscal_till_connections WHERE device = 'sign_fr'")
    execute("DELETE FROM fiscal_network_connections WHERE provider = 'fiskaly'")

    drop constraint(:fiscal_till_signatures, :fiscal_till_signatures_check)

    create constraint(:fiscal_till_signatures, :fiscal_till_signatures_check,
             check: """
             device IN ('tse', 'rksv')
             AND kind IN ('receipt', 'start', 'null', 'monthly', 'yearly', 'closing')
             AND status IN ('pending', 'sending', 'signed', 'uncertain', 'device_failed',
                            'rejected', 'failed')
             AND attempts >= 0
             AND (kind = 'receipt') = (document_id IS NOT NULL)
             AND (kind <> 'receipt' OR period IS NULL)
             AND (status <> 'signed' OR signature_value IS NOT NULL)
             AND (status <> 'device_failed' OR failed_at IS NOT NULL)
             """
           )

    drop constraint(:fiscal_till_connections, :fiscal_till_connections_check)

    create constraint(:fiscal_till_connections, :fiscal_till_connections_check,
             check: """
             device IN ('tse', 'rksv') AND provider IN ('sandbox', 'fiskaly')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('provisioning', 'active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR (api_key IS NOT NULL AND api_secret IS NOT NULL))
             AND (status <> 'active' OR provisioned_at IS NOT NULL)
             """
           )

    drop constraint(:fiscal_network_connections, :fiscal_network_connections_check)

    create constraint(:fiscal_network_connections, :fiscal_network_connections_check,
             check: """
             network IN ('peppol') AND provider IN ('sandbox', 'storecove')
             AND environment IN ('sandbox', 'test', 'production')
             AND status IN ('active', 'invalid')
             AND (provider = 'sandbox') = (environment = 'sandbox')
             AND (environment = 'sandbox' OR (api_key IS NOT NULL AND legal_entity_id IS NOT NULL))
             """
           )

    alter table(:fiscal_network_connections) do
      remove :api_secret
    end
  end
end
