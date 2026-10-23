defmodule Palee.Perks.Ports.PerkStore do
  @moduledoc """
  Persistence port of partner perks, their versions, code pools and the
  members' claims (ADR-191). Every call runs in the caller's `RepoContext`:
  the business's scope (`organization_id`, with the member's `user_id` when
  a member acts). The partner's verification link runs in the business
  scope its signed token names.

  Perks come back with their current version loaded (`perk.version`).

  Writes that guard caps or versions are atomic: `revise_perk/4`,
  `claim/4`, `use_claim/6` and `revoke_claim/4` hold a row lock on the perk
  for the whole decision, so caps, the code pool, versioning and the single
  use hold however many requests race.
  """

  alias Palee.Perks.{Perk, PerkClaim, PerkVersion}

  @type context :: map()
  @type id :: binary()

  @doc "Inserts a perk and its version 1 in one transaction."
  @callback create_perk(context(), map(), map()) ::
              {:ok, Perk.t()} | {:error, Ecto.Changeset.t()}

  @doc """
  Changes a perk's own fields and, with `version_attrs`, its documents:
  amended in place while nobody claimed, a new version otherwise
  (`PerkRules.version_mode/1` on the locked row).
  """
  @callback revise_perk(context(), Perk.t(), map(), map() | nil) ::
              {:ok, Perk.t()} | {:error, Ecto.Changeset.t() | atom()}

  @callback set_status(context(), Perk.t(), map()) ::
              {:ok, Perk.t()} | {:error, Ecto.Changeset.t()}
  @doc "Deletes a perk that has no claims; `{:error, :perk_has_claims}` otherwise."
  @callback delete_perk(context(), Perk.t()) :: :ok | {:error, :perk_has_claims}
  @callback get_perk(context(), id()) :: Perk.t() | nil
  @doc "The business's perks, newest first, filtered by `statuses` and `ids`."
  @callback list_perks(context(), %{optional(:statuses) => [String.t()], optional(:ids) => [id()]}) ::
              [Perk.t()]
  @doc "Every version of a perk, newest first."
  @callback list_versions(context(), id()) :: [PerkVersion.t()]
  @doc "Versions by `{perk_id, version}`."
  @callback get_versions(context(), [{id(), pos_integer()}]) :: %{
              {id(), pos_integer()} => PerkVersion.t()
            }

  @doc "Adds codes to a perk's pool, skipping ones it already holds."
  @callback add_codes(context(), id(), [String.t()]) :: {:ok, %{added: non_neg_integer()}}
  @doc "Pool sizes per perk: `%{perk_id => %{total, free}}`."
  @callback code_stats(context(), [id()]) :: %{
              id() => %{total: non_neg_integer(), free: non_neg_integer()}
            }

  @doc """
  Claims a perk for `user_id` atomically. Under a lock on the perk row,
  `decide` gets the locked perk (current version loaded) and
  `%{member_claims, open_claim, count_since}`: the member's claims that
  count (not revoked), their unused one if any, and a function giving
  `%{member, all}` claims made since a UTC moment. It answers
  `{:existing, claim}`, `{:new, attrs}` (`code`, `token_hash`,
  `claimed_at`) or `{:error, reason}`. A code-pool claim takes the oldest
  free pool code (`{:error, :perk_codes_exhausted}` when none is left);
  `claims_count` grows in the same transaction. Returns
  `{:ok, %{perk, claim, new?, free_codes}}` (`free_codes` for a pool, else nil).
  """
  @callback claim(context(), id(), id(), (Perk.t(), map() -> term())) ::
              {:ok, %{perk: Perk.t(), claim: PerkClaim.t(), new?: boolean(), free_codes: integer() | nil}}
              | {:error, term()}

  @doc """
  Marks a claim used once: under locks on the perk and the claim, `check`
  gets both and answers `:ok` or `{:error, reason}`; the claim becomes
  `used` only if it was unused (`{:error, :perk_claim_already_used}`) and
  its token is cleared; `uses_count` grows in the same transaction.
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
  Replaces the secret behind a personal QR claim's link (the previous link
  stops working). Only the claim's own member, only while unused.
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
  @doc "The business's club groups and channels (what eligibility may name)."
  @callback group_ids(context()) :: [id()]
  @doc "The club groups (community channels) the member belongs to at the business."
  @callback member_group_ids(context(), id()) :: [id()]
  @doc "The first word of the member's display name (the partner sees nothing more)."
  @callback member_first_name(context(), id()) :: String.t() | nil
end
