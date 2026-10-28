defmodule Palee.Email.Commands.Unsubscribe do
  @moduledoc """
  The one-click unsubscribe of transactional mail (ADR-212, RFC 8058).

  `url/3` is the link a transactional email carries in its
  `List-Unsubscribe` header and its footer; `call/1` (the link's POST)
  opts the address out of that kind of email. Security and account mail
  carry no such link and ignore opt-outs.
  """

  alias Palee.Application.{KeyDerivation, PublicURL}
  alias Palee.Email.Domain.{Address, UnsubscribeToken}

  @path "/api/email/unsubscribe/"

  @doc "The unsubscribe URL for `kind` mail to `address`, its page in `locale`."
  def url(address, kind, locale) do
    token =
      UnsubscribeToken.sign(key(), %{
        digest: Address.digest(address),
        kind: to_string(kind),
        locale: locale || "en"
      })

    PublicURL.base_url() <> @path <> token
  end

  @doc "`{:ok, %{kind, locale}}` for a valid token, without acting on it."
  def peek(token) do
    case UnsubscribeToken.verify(key(), token) do
      {:ok, claims} -> {:ok, Map.take(claims, [:kind, :locale])}
      :error -> {:error, :invalid}
    end
  end

  @doc "Opts the token's address out of its kind: `{:ok, %{kind, locale}}` or `{:error, :invalid}`."
  def call(token) do
    case UnsubscribeToken.verify(key(), token) do
      {:ok, %{digest: digest, kind: kind} = claims} ->
        :ok = Palee.Email.message_store().opt_out(digest, kind)
        :telemetry.execute([:palee, :email, :unsubscribed], %{count: 1}, %{kind: kind})
        {:ok, Map.take(claims, [:kind, :locale])}

      :error ->
        {:error, :invalid}
    end
  end

  defp key, do: KeyDerivation.derive("email-unsubscribe", "v1")
end
