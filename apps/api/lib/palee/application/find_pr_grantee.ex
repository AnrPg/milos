defmodule Palee.Application.FindPRGrantee do
  @moduledoc """
  Global grantee lookup for PR sharing (ADR-132, TD-091).

  ADR-129 lets an owner share their PR table with any account, but the picker
  only searched co-members of the selected gym. This finds an account outside
  one's gyms by its EXACT nickname - never a prefix or fuzzy search, so it
  cannot enumerate accounts. It reveals nothing beyond what the public
  nickname-availability check already does (whether a nickname is taken) plus
  the account id needed to create the grant: no avatar, no email, no gyms.
  Looking up oneself answers like an unknown nickname.
  """

  alias Palee.Identity
  alias Palee.Identity.RegistrationPolicy

  @max_length 64

  def call(%{user_id: user_id}, nickname) when is_binary(user_id) do
    with {:ok, nickname} <- normalize(nickname) do
      case Identity.find_by_nickname(nickname) do
        %{id: ^user_id} -> {:ok, %{grantee: nil}}
        %{} = user -> {:ok, %{grantee: profile(user)}}
        nil -> {:ok, %{grantee: nil}}
      end
    end
  end

  def call(_context, _nickname), do: {:error, :missing_ownership_scope}

  defp normalize(nickname) when is_binary(nickname) and byte_size(nickname) <= @max_length do
    case nickname |> String.trim() |> RegistrationPolicy.normalize_nickname() do
      "" -> {:error, :bad_request}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize(_nickname), do: {:error, :bad_request}

  defp profile(user) do
    %{
      id: user.id,
      nickname: user.nickname,
      display_nickname: Map.get(user, :display_nickname) || user.nickname
    }
  end
end
