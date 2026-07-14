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

  def resource_from_claims(%{"sub" => id}) do
    case Identity.find_by_id(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end
end
