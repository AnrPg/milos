defmodule Mix.Tasks.Milos.Platform.RevokeVendor do
  use Mix.Task

  @shortdoc "Revokes vendor (SaaS-owner) access from an account"

  @moduledoc """
  The symmetric counterpart to `mix milos.platform.grant_vendor` (F-12).

  Without this, offboarding a platform operator required editing the
  `vendors` table by hand. Like the grant task this has no HTTP surface:
  vendor status is only reachable from a shell on the host.

  Revoking flips `status` to `:revoked` rather than deleting the row, so the
  grant remains auditable. `OrganizationStore.get_vendor/1` only matches
  `status: :active`, so the account loses platform access immediately.

      mix milos.platform.revoke_vendor NICKNAME
  """

  @impl Mix.Task
  def run([nickname]) do
    Mix.Task.run("app.start")

    with %{} = user <- MilosTraining.Identity.find_by_nickname(nickname),
         {:ok, vendor} <- MilosTraining.Organizations.revoke_vendor(user.id) do
      Mix.shell().info("Vendor revoked: #{nickname} (#{vendor.user_id})")
    else
      nil -> Mix.raise("Account not found: #{nickname}")
      {:error, :not_found} -> Mix.raise("Account is not a vendor: #{nickname}")
      {:error, reason} -> Mix.raise("Could not revoke vendor: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix milos.platform.revoke_vendor NICKNAME")
end
