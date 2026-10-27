defmodule Palee.Email.LinkTokens do
  @moduledoc """
  Single-use email links (ADR-203): issue one, consume it once, or peek at
  it without spending it (a confirmation page that asks "are you sure?").

  Purposes and their default lifetimes are in `LinkTokenPolicy`:
  `verify_email` (48 h), `email_change` (24 h), `email_change_revert`
  (7 days, never replaced), `password_reset` (1 h), `account_deletion`
  (24 h), `sign_out_everywhere` (7 days, never replaced; ADR-208). An unknown purpose raises
  `ArgumentError` on `issue/3` and is `{:error, :invalid}` elsewhere.

  The raw token is returned once, by `issue/3`, to be put in the link; only
  its SHA-256 is stored.
  """

  alias Palee.Email.Domain.LinkTokenPolicy
  alias Palee.Email.LinkToken

  @type purpose :: atom() | String.t()

  @doc """
  Issues a link for `login_id`. Options: `:user_id`, `:target_email` (the
  address the link proves, e.g. the new address of an email change),
  `:metadata` (a JSON map), `:ttl_seconds` (overrides the purpose's) and
  `:now`. For purposes that replace (all but `email_change_revert`) the
  login's older unused links of the purpose stop working.
  """
  @spec issue(purpose(), binary(), keyword()) ::
          {:ok, String.t(), LinkToken.t()} | {:error, term()}
  def issue(purpose, login_id, opts \\ []) when is_binary(login_id) do
    purpose = known!(purpose)
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    raw = LinkTokenPolicy.generate()

    attrs = %{
      purpose: purpose,
      login_id: login_id,
      user_id: Keyword.get(opts, :user_id),
      target_email: Keyword.get(opts, :target_email),
      token_hash: LinkTokenPolicy.hash(raw),
      expires_at: LinkTokenPolicy.expires_at(purpose, now, Keyword.get(opts, :ttl_seconds)),
      metadata: Keyword.get(opts, :metadata, %{}),
      inserted_at: now
    }

    with {:ok, token} <-
           store().insert(attrs, replace_previous: LinkTokenPolicy.replaces_previous?(purpose)) do
      {:ok, raw, token}
    end
  end

  @doc """
  Spends the link: `{:ok, record}` exactly once, then `{:error, :used}`;
  `{:error, :expired}` past its lifetime, `{:error, :invalid}` for an
  unknown token or a token of another purpose. Atomic under concurrency.
  """
  @spec consume(purpose(), String.t(), DateTime.t()) ::
          {:ok, LinkToken.t()} | {:error, :invalid | :expired | :used}
  def consume(purpose, raw, now \\ DateTime.utc_now()) do
    with {:ok, purpose, hash} <- lookup_key(purpose, raw) do
      case store().consume(purpose, hash, now) do
        %LinkToken{} = token -> {:ok, token}
        nil -> explain(purpose, hash, now)
      end
    end
  end

  @doc "What `consume/3` would answer, without spending the link."
  @spec peek(purpose(), String.t(), DateTime.t()) ::
          {:ok, LinkToken.t()} | {:error, :invalid | :expired | :used}
  def peek(purpose, raw, now \\ DateTime.utc_now()) do
    with {:ok, purpose, hash} <- lookup_key(purpose, raw) do
      case store().get_by_hash(purpose, hash) do
        nil ->
          {:error, :invalid}

        token ->
          with :ok <- LinkTokenPolicy.check(token, now), do: {:ok, token}
      end
    end
  end

  @doc "The purposes links can be issued for."
  defdelegate purposes(), to: LinkTokenPolicy

  defp explain(purpose, hash, now) do
    case store().get_by_hash(purpose, hash) do
      nil -> {:error, :invalid}
      token -> with :ok <- LinkTokenPolicy.check(token, now), do: {:error, :invalid}
    end
  end

  defp lookup_key(purpose, raw) do
    with {:ok, purpose} <- LinkTokenPolicy.purpose(purpose),
         true <- LinkTokenPolicy.well_formed?(raw) do
      {:ok, purpose, LinkTokenPolicy.hash(raw)}
    else
      _invalid -> {:error, :invalid}
    end
  end

  defp known!(purpose) do
    case LinkTokenPolicy.purpose(purpose) do
      {:ok, purpose} -> purpose
      :error -> raise ArgumentError, "unknown email link purpose #{inspect(purpose)}"
    end
  end

  defp store, do: Application.fetch_env!(:palee, :email_link_token_store)
end
