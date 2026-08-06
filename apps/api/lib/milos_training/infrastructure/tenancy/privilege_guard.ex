defmodule MilosTraining.Infrastructure.Tenancy.PrivilegeGuard do
  @moduledoc """
  Row Level Security only enforces tenant isolation if the runtime database
  connection is neither a superuser nor BYPASSRLS. In production this is
  enforced by the `milos_runtime` role (see ops/postgres/init), but nothing
  previously verified that at boot - a misconfigured DATABASE_URL pointing at
  a superuser role would silently disable every RLS policy in the app.
  """

  require Logger

  alias MilosTraining.Repo

  def check! do
    case privileges() do
      {:ok, role, false, false} ->
        Logger.info("PrivilegeGuard: runtime role #{role} is non-superuser, non-bypassrls - RLS enforced")
        :ok

      {:ok, role, superuser?, bypassrls?} ->
        message =
          "PrivilegeGuard: runtime DB role #{role} has rolsuper=#{superuser?} " <>
            "rolbypassrls=#{bypassrls?} - Row Level Security is NOT enforced for this connection"

        if prod?() do
          raise message
        else
          Logger.warning(message <> " (allowed outside prod)")
          :ok
        end

      {:error, reason} ->
        Logger.warning("PrivilegeGuard: could not verify runtime role privileges: #{inspect(reason)}")
        :ok
    end
  end

  defp privileges do
    case Ecto.Adapters.SQL.query(
           Repo,
           "SELECT current_user, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user), (SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user)",
           []
         ) do
      {:ok, %{rows: [[role, superuser?, bypassrls?]]}} -> {:ok, role, superuser?, bypassrls?}
      {:error, reason} -> {:error, reason}
    end
  end

  defp prod?, do: Application.get_env(:milos_training, :app_env) == :prod
end
