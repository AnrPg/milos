defmodule Palee.Identity.PasswordHasher do
  def hash(password), do: impl().hash(password)

  defp impl do
    Application.fetch_env!(:palee, :identity_password_hasher)
  end
end
