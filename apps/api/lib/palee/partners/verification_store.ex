defmodule Palee.Partners.VerificationStore do
  @moduledoc """
  Facade over the configured verification adapter (ADR-280). Each call
  opens the session its caller acts in: the person themselves or a vendor
  (`%{user_id: id}`, through `RepoContext.run`), or `:system` (no acting
  person: the daily job and account deletion). Row security decides what
  each session sees.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext

  @type scope :: %{required(:user_id) => Ecto.UUID.t(), optional(atom()) => term()} | :system

  defp adapter, do: Application.fetch_env!(:palee, :partner_verification_store)

  @doc "Runs `fun` in the scope's session."
  def run(:system, fun) when is_function(fun, 0), do: fun.()

  def run(%{user_id: user_id}, fun) when is_binary(user_id) and is_function(fun, 0),
    do: RepoContext.run(%{user_id: user_id}, fun)

  def run(_scope, _fun), do: {:error, :missing_ownership_scope}

  @doc "Runs `fun` in one transaction of the scope's session; `{:ok, value}` or `{:error, reason}`."
  def transaction(scope, fun) when is_function(fun, 0),
    do: run(scope, fn -> adapter().transaction(fun) end)

  defp call(scope, function, args), do: run(scope, fn -> apply(adapter(), function, args) end)

  # Verifications.
  def get_verification(scope, user_id), do: call(scope, :get_verification, [user_id])
  def verify_by_membership(scope), do: call(scope, :verify_by_membership, [])
  def verification_badges(scope, ids), do: call(scope, :verification_badges, [ids])
  def sponsor_standing(scope, ids, since), do: call(scope, :sponsor_standing, [ids, since])
  def insert_verification(scope, attrs), do: call(scope, :insert_verification, [attrs])

  def update_verification(scope, verification, changes),
    do: call(scope, :update_verification, [verification, changes])

  def list_verifications(scope, ids), do: call(scope, :list_verifications, [ids])

  # Requests.
  def get_request(scope, id), do: call(scope, :get_request, [id])
  def latest_request(scope, user_id), do: call(scope, :latest_request, [user_id])
  def create_request(scope, attrs), do: call(scope, :create_request, [attrs])
  def update_request(scope, request, changes), do: call(scope, :update_request, [request, changes])
  def list_requests(scope, status, limit), do: call(scope, :list_requests, [status, limit])

  def requests_with_selfies_before(scope, cutoff),
    do: call(scope, :requests_with_selfies_before, [cutoff])

  def requests_of(scope, user_id), do: call(scope, :requests_of, [user_id])

  # Phone codes.
  def count_codes_since(scope, user_id, since),
    do: call(scope, :count_codes_since, [user_id, since])

  def insert_code(scope, attrs), do: call(scope, :insert_code, [attrs])
  def latest_code(scope, request_id), do: call(scope, :latest_code, [request_id])
  def update_code(scope, code, changes), do: call(scope, :update_code, [code, changes])
  def delete_code(scope, code), do: call(scope, :delete_code, [code])
  def delete_codes_before(scope, cutoff), do: call(scope, :delete_codes_before, [cutoff])

  # Sponsorships.
  def get_sponsorship(scope, id), do: call(scope, :get_sponsorship, [id])

  def sponsorship_between(scope, candidate_id, sponsor_id),
    do: call(scope, :sponsorship_between, [candidate_id, sponsor_id])

  def sponsorships_of_candidate(scope, candidate_id),
    do: call(scope, :sponsorships_of_candidate, [candidate_id])

  def sponsorships_of_sponsor(scope, sponsor_id, statuses),
    do: call(scope, :sponsorships_of_sponsor, [sponsor_id, statuses])

  def count_vouches_since(scope, sponsor_id, since),
    do: call(scope, :count_vouches_since, [sponsor_id, since])

  def insert_sponsorship(scope, attrs), do: call(scope, :insert_sponsorship, [attrs])

  def update_sponsorship(scope, sponsorship, changes),
    do: call(scope, :update_sponsorship, [sponsorship, changes])

  def delete_open_sponsorships(scope, candidate_id),
    do: call(scope, :delete_open_sponsorships, [candidate_id])

  def vouched_sponsor_ids(scope, candidate_id),
    do: call(scope, :vouched_sponsor_ids, [candidate_id])

  # Links.
  def insert_link(scope, attrs), do: call(scope, :insert_link, [attrs])
  def delete_links(scope, candidate_id), do: call(scope, :delete_links, [candidate_id])
  def find_link(scope, digest), do: call(scope, :find_link, [digest])
  def redeem_link(scope, digest, now), do: call(scope, :redeem_link, [digest, now])

  # Account deletion.
  def purge_person(scope, user_id), do: call(scope, :purge_person, [user_id])
end
