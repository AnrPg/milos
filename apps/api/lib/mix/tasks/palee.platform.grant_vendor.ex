defmodule Mix.Tasks.Palee.Platform.GrantVendor do
  use Mix.Task

  @shortdoc "Grants vendor (SaaS-owner) access to an existing account"

  @impl Mix.Task
  def run([nickname]) do
    Mix.Task.run("app.start")

    with %{} = user <- Palee.Identity.find_by_nickname(nickname),
         {:ok, vendor} <- Palee.Organizations.grant_vendor(user.id) do
      Mix.shell().info("Vendor ready: #{nickname} (#{vendor.user_id})")
    else
      nil -> Mix.raise("Account not found: #{nickname}")
      {:error, reason} -> Mix.raise("Could not grant vendor: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix palee.platform.grant_vendor NICKNAME")
end
