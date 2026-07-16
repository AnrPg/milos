defmodule MilosTraining.Infrastructure.Auth.Guardian do
  use Guardian, otp_app: :milos_training

  alias MilosTraining.Identity

  def subject_for_token(user, _claims), do: {:ok, user.id}

  def fetch_issuer do
    System.get_env("GUARDIAN_ISSUER", "milos_training")
  end

  def fetch_secret do
    System.get_env("GUARDIAN_SECRET_KEY") ||
      if Application.get_env(:milos_training, :env, :prod) in [:dev, :test] do
        "dev-guardian-secret-change-me"
      else
        raise "GUARDIAN_SECRET_KEY environment variable is not set."
      end
  end

  def resource_from_claims(%{"sub" => id} = claims) do
    case Identity.find_by_id(id) do
      nil -> {:error, :not_found}
      user -> validate_security_version(user, claims)
    end
  end

  defp validate_security_version(user, %{"sv" => version})
       when version == user.security_version,
       do: {:ok, user}

  defp validate_security_version(_user, %{"sv" => _version}), do: {:error, :invalid_token}

  # Transitional compatibility for tokens issued before the security-version migration.
  # They naturally expire within the access/refresh TTL and cannot bypass a version bump.
  defp validate_security_version(%{security_version: 1} = user, _legacy_claims), do: {:ok, user}
  defp validate_security_version(_user, _legacy_claims), do: {:error, :invalid_token}
end
