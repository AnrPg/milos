defmodule Palee.Infrastructure.Email.EctoLinkTokenStore do
  @moduledoc """
  Ecto adapter of single-use email links (ADR-203). Consuming is one
  `UPDATE ... WHERE used_at IS NULL AND expires_at > now RETURNING`, so of
  two racing requests exactly one gets the link.
  """

  @behaviour Palee.Email.Ports.LinkTokenStore

  import Ecto.Query

  alias Palee.Email.LinkToken
  alias Palee.Repo

  @impl true
  def insert(attrs, opts) do
    Repo.transaction(fn ->
      if Keyword.get(opts, :replace_previous, false) do
        LinkToken
        |> where([t], t.login_id == ^attrs.login_id and t.purpose == ^attrs.purpose)
        |> where([t], is_nil(t.used_at))
        |> Repo.delete_all()
      end

      LinkToken
      |> struct(attrs)
      |> Repo.insert()
      |> case do
        {:ok, token} -> token
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @impl true
  def consume(purpose, token_hash, %DateTime{} = now) do
    LinkToken
    |> where([t], t.purpose == ^purpose and t.token_hash == ^token_hash)
    |> where([t], is_nil(t.used_at) and t.expires_at > ^now)
    |> select([t], t)
    |> Repo.update_all(set: [used_at: now])
    |> case do
      {1, [token]} -> token
      {0, []} -> nil
    end
  end

  @impl true
  def get_by_hash(purpose, token_hash),
    do: Repo.get_by(LinkToken, purpose: purpose, token_hash: token_hash)
end
