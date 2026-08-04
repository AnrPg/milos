defmodule Mix.Tasks.Milos.Platform.GrantOwner do
  use Mix.Task

  @shortdoc "Grants platform-owner access to an existing account"

  @impl Mix.Task
  def run([nickname]) do
    Mix.Task.run("app.start")

    with %{} = user <- MilosTraining.Identity.find_by_nickname(nickname),
         {:ok, owner} <- MilosTraining.Organizations.grant_platform_owner(user.id) do
      Mix.shell().info("Platform owner ready: #{nickname} (#{owner.user_id})")
    else
      nil -> Mix.raise("Account not found: #{nickname}")
      {:error, reason} -> Mix.raise("Could not grant platform owner: #{inspect(reason)}")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix milos.platform.grant_owner NICKNAME")
end
