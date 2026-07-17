defmodule MilosTraining.Application.RegisterAdmin do
  alias MilosTraining.Application.TokenIssuer
  alias MilosTraining.Identity
  alias MilosTraining.Identity.Domain.AdminRegistrationPolicy

  def call(params) when is_map(params) do
    with :ok <- authorize(params),
         {:ok, user} <- Identity.register_admin(registration_params(params)),
         {:ok, tokens} <- issue_tokens_or_cleanup(user) do
      {:ok, Map.put(tokens, :user, user)}
    end
  end

  defp authorize(params) do
    AdminRegistrationPolicy.authorize(
      value(params, :admin_code),
      Application.fetch_env!(:milos_training, :admin_registration_code)
    )
  end

  defp registration_params(params) do
    %{
      nickname: value(params, :nickname),
      password: value(params, :password),
      role: :admin
    }
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp issue_tokens_or_cleanup(user) do
    case TokenIssuer.issue_pair(user) do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, :token_issuance_failed} ->
        case Identity.delete(user) do
          :ok -> {:error, :token_issuance_failed}
          {:error, _reason} -> {:error, :registration_cleanup_failed}
        end
    end
  end
end
