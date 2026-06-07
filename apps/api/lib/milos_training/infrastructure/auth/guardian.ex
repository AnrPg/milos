defmodule MilosTraining.Infrastructure.Auth.Guardian do
  use Guardian, otp_app: :milos_training

  alias MilosTraining.Identity

  def subject_for_token(user, _claims), do: {:ok, user.id}

  def fetch_issuer do
    System.get_env("GUARDIAN_ISSUER", "milos_training")
  end

  def fetch_secret do
    case System.get_env("GUARDIAN_SECRET_KEY") do
      nil ->
        if System.get_env("MIX_ENV") == "prod" do
          raise "environment variable GUARDIAN_SECRET_KEY is missing"
        else
          "dev-guardian-secret-change-me"
        end

      secret ->
        secret
    end
  end

  def resource_from_claims(%{"sub" => id}) do
    case Identity.find_by_id(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
