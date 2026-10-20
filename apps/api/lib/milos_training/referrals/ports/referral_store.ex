defmodule MilosTraining.Referrals.Ports.ReferralStore do
  @moduledoc """
  Persistence port for invite codes and invites (ADR-156). Every call runs
  in the caller's `RepoContext`: the box's scope for its invites, the
  person's for their own; `resolve_code/1` is the one public lookup.
  """

  alias MilosTraining.Referrals.{ReferralAttribution, ReferralCode}

  @type context :: map()
  @type id :: binary()

  @callback get_active_code(context(), id()) :: ReferralCode.t() | nil
  @callback insert_code(context(), map()) :: {:ok, ReferralCode.t()} | {:error, term()}
  @callback revoke_code(context(), ReferralCode.t(), DateTime.t()) ::
              {:ok, ReferralCode.t()} | {:error, term()}

  @doc """
  Who a live code belongs to, from any scope: `%{code_id, organization_id,
  user_id, box}` (the box's slug, name, logo, colour and whether its page is
  published), or nil for a revoked code, a former member or a closed box.
  """
  @callback resolve_code(String.t()) :: %{code_id: id(), organization_id: id(), user_id: id(), box: map()} | nil

  @callback get_attribution(context(), id()) :: ReferralAttribution.t() | nil
  @doc "The friend's invite at the box in scope."
  @callback get_attribution_for(context(), id()) :: ReferralAttribution.t() | nil
  @callback insert_attribution(context(), map()) ::
              {:ok, ReferralAttribution.t()} | {:error, Ecto.Changeset.t()}
  @doc "Replaces an invite that ran out with a new one, keeping its id."
  @callback replace_attribution(context(), ReferralAttribution.t(), map()) ::
              {:ok, ReferralAttribution.t()} | {:error, Ecto.Changeset.t()}
  @callback update_attribution(context(), ReferralAttribution.t(), map()) ::
              {:ok, ReferralAttribution.t()} | {:error, Ecto.Changeset.t()}

  @doc "The box's invites, newest first, filtered by member, statuses and a limit."
  @callback list_attributions(context(), %{
              optional(:referrer_user_id) => id(),
              optional(:statuses) => [String.t()],
              optional(:awaiting_review) => boolean(),
              optional(:limit) => pos_integer()
            }) :: [ReferralAttribution.t()]

  @doc "Counts per status of the box's invites made since a moment."
  @callback stats(context(), DateTime.t()) :: %{String.t() => non_neg_integer()}

  @doc "Runs `fun` in one transaction holding a lock on one friend at the box."
  @callback with_friend_lock(context(), id(), (-> result)) :: result when result: term()
end
