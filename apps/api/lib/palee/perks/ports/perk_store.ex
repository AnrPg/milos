defmodule Palee.Perks.Ports.PerkStore do
  @moduledoc """
  Persistence port of partner perks, their code pools and the members'
  claims (ADR-191). Every call runs in the caller's `RepoContext`: the
  business's scope (`organization_id`), with the member's `user_id` when a
  member acts. The partner's verification link runs in the business scope
  its signed token names.

  The two writes that guard caps are atomic: `claim/4` and `use_claim/6`
  hold a row lock on the perk for the whole decision, so the overall cap,
  the per-member cap, the code pool and the single use hold however many
  requests race.
  """

  alias Palee.Perks.{Perk, PerkClaim}

  @type context :: map()
  @type id :: binary()

  @callback create_perk(context(), map()) :: {:ok, Perk.t()} | {:error, Ecto.Changeset.t()}
  @callback update_perk(context(), Perk.t(), map()) ::
              {:ok, Perk.t()} | {:error, Ecto.Changeset.t()}
  @doc "Writes a lifecycle step's changes."
  @callback set_status(context(), Perk.t(), map()) ::
              {:ok, Perk.t()} | {:error, Ecto.Changeset.t()}
  @doc "Deletes a perk that has no claims; `{:error, :perk_has_claims}` otherwise."
  @callback delete_perk(context(), Perk.t()) :: :ok | {:error, :perk_has_claims}
  @callback get_perk(context(), id()) :: Perk.t() | nil
  @doc "The business's perks, newest first, filtered by `statuses` and `ids`."
  @callback list_perks(context(), %{optional(:statuses) => [String.t()], optional(:ids) => [id()]}) ::
              [Perk.t()]

  @doc "Adds codes to a perk's pool, skipping ones it already holds."
  @callback add_codes(context(), id(), [String.t()]) ::
              {:ok, %{added: non_neg_integer(), duplicates: non_neg_integer()}}
  @doc "Pool sizes per perk: `%{perk_id => %{total, free}}`."
  @callback code_stats(context(), [id()]) :: %{
              id() => %{total: non_neg_integer(), free: non_neg_integer()}
            }

  @doc """
  Claims a perk for `user_id` atomically. Under a lock on the perk row,
  `decide` gets the locked perk and `%{member_claims, open_claim}` (the
  member's claims that count, not revoked, and their unused one if any) and
  answers `{:existing, claim}`, `{:new, attrs}` (the claim's code, token
  hash, time) or `{:error, reason}`. For a new claim of a unique-code perk
  the oldest free pool code becomes its code (`{:error, :perk_codes_exhausted}`
  when none is left); the perk's `claims_count` grows in the same
  transaction. Returns `{:ok, %{perk, claim, new?}}`.
  """
  @callback claim(
              context(),
              id(),
              id(),
              (Perk.t(), %{member_claims: non_neg_integer(), open_claim: PerkClaim.t() | nil} ->
                 {:existing, PerkClaim.t()} | {:new, map()} | {:error, atom()})
            ) :: {:ok, %{perk: Perk.t(), claim: PerkClaim.t(), new?: boolean()}} | {:error, term()}

  @doc """
  Marks a claim used once: under locks on the claim and its perk, `check`
  gets both and answers `:ok` or `{:error, reason}`; the claim becomes
  `used` only if it was unused (`{:error, :perk_claim_already_used}`), and
  the perk's `uses_count` grows in the same transaction.
  """
  @callback use_claim(
              context(),
              id(),
              String.t(),
              id() | nil,
              DateTime.t(),
              (Perk.t(), PerkClaim.t() -> :ok | {:error, atom()})
            ) :: {:ok, %{perk: Perk.t(), claim: PerkClaim.t()}} | {:error, term()}

  @doc "Revokes an unused claim and gives its place back to the overall cap."
  @callback revoke_claim(context(), id(), id(), DateTime.t()) ::
              {:ok, %{perk: Perk.t(), claim: PerkClaim.t()}} | {:error, term()}

  @doc """
  Replaces the secret behind a QR claim's verification link (the previous
  link stops working). Only the claim's own member, only while unused:
  `{:error, :perk_claim_not_open}` otherwise.
  """
  @callback rotate_token(context(), id(), id(), String.t()) ::
              {:ok, PerkClaim.t()} | {:error, :perk_claim_not_open}

  @callback get_claim(context(), id()) :: PerkClaim.t() | nil
  @doc "The member's claims at the business, newest first."
  @callback list_member_claims(context(), id()) :: [PerkClaim.t()]

  @doc """
  A perk's claims for the export, oldest first, each with the member's
  `display_name` and `handle`, after an optional cursor (`claimed_at`, id).
  """
  @callback list_claims(context(), id(), %{
              optional(:limit) => pos_integer(),
              optional(:after) => {DateTime.t(), id()}
            }) :: [map()]

  @doc "The packages the member holds now (active or paused, not ended) at the business."
  @callback member_package_ids(context(), id(), Date.t()) :: [id()]
end
