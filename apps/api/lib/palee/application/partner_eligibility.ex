defmodule Palee.Application.PartnerEligibility do
  @moduledoc """
  Who may take part in Partners (ADR-280): the seam the deck side calls.

  A person is verified once and for good, by an active membership (checked
  on first use through `palee_partner_verify_by_membership()`) or by two
  sponsors and a check by the Palee team. Only a suspension by the Palee
  team takes it away; then every sponsor who vouched for that person is
  told and cannot vouch for 60 days.
  """

  alias Palee.Application.PartnerVerificationNotices
  alias Palee.Partners.Verifications

  @type status :: :verified | :needs_verification | :in_review | :rejected | :suspended

  @doc "The viewer's verification state and next step."
  @spec status(map()) :: %{status: status(), method: String.t() | nil, next_step: atom() | nil}
  def status(%{user_id: user_id} = context) do
    scope = scope(context)
    verification = verification(scope)
    request = Verifications.latest_request(scope, user_id)
    Verifications.status(verification, request, vouches(scope, user_id, verification))
  end

  @doc "`:ok` when the viewer may use Partners."
  @spec require_verified(map()) ::
          :ok | {:error, :partner_verification_required} | {:error, :partner_suspended}
  def require_verified(%{user_id: user_id} = context) when is_binary(user_id),
    do: context |> scope() |> verification() |> Verifications.require_verified()

  def require_verified(_context), do: {:error, :partner_verification_required}

  @doc "The ids among `user_ids` that are verified and not suspended."
  @spec verified_user_ids([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  def verified_user_ids([]), do: []

  def verified_user_ids(user_ids) when is_list(user_ids) do
    badges = verification_badges(user_ids)
    user_ids |> Enum.uniq() |> Enum.filter(&Map.has_key?(badges, &1))
  end

  @doc "Per person: how they were verified and the box of an active membership (nil if none)."
  @spec verification_badges([Ecto.UUID.t()]) :: %{
          Ecto.UUID.t() => %{method: String.t(), box_name: String.t() | nil}
        }
  def verification_badges([]), do: %{}

  def verification_badges(user_ids) when is_list(user_ids),
    do: Verifications.verification_badges(:system, valid_ids(user_ids))

  @doc "The Palee team suspends a person: verification off, sponsors penalised and told."
  @spec suspend(map(), Ecto.UUID.t(), DateTime.t()) ::
          {:ok, %{penalized_sponsor_ids: [Ecto.UUID.t()]}} | {:error, term()}
  def suspend(%{user_id: actor_id}, user_id, %DateTime{} = now) do
    scope = %{user_id: actor_id}
    until = Verifications.penalty_until(now)

    result =
      Verifications.transaction(scope, fn ->
        with %{} = verification <-
               Verifications.get_verification(scope, user_id) || {:error, :not_found},
             {:ok, _suspended} <-
               Verifications.update_verification(scope, verification, %{
                 status: "suspended",
                 suspended_at: now,
                 suspended_by_id: actor_id
               }) do
          {:ok, penalize(scope, Verifications.vouched_sponsor_ids(scope, user_id), until)}
        end
      end)

    with {:ok, sponsor_ids} <- result do
      Enum.each(sponsor_ids, &PartnerVerificationNotices.sponsor_penalty(&1, until))
      {:ok, %{penalized_sponsor_ids: sponsor_ids}}
    end
  end

  defp penalize(_scope, [], _until), do: []

  defp penalize(scope, sponsor_ids, until) do
    scope
    |> Verifications.list_verifications(sponsor_ids)
    |> Enum.map(fn verification ->
      {:ok, _updated} =
        Verifications.update_verification(scope, verification, %{
          sponsor_penalty_until:
            Verifications.extend_penalty(verification.sponsor_penalty_until, until)
        })

      verification.user_id
    end)
  end

  @doc false
  # The person's verification, verifying them by a membership on first use.
  def verification(scope) do
    case Verifications.verify_by_membership(scope) do
      %{} = verification -> verification
      nil -> Verifications.get_verification(scope, scope.user_id)
    end
  end

  defp vouches(_scope, _user_id, %{status: _verified_or_suspended}), do: 0

  defp vouches(scope, user_id, nil),
    do: scope |> Verifications.sponsorships_of_candidate(user_id) |> Verifications.vouch_count()

  defp scope(%{user_id: user_id}), do: %{user_id: user_id}

  defp valid_ids(ids) do
    ids
    |> Enum.flat_map(fn id ->
      case Ecto.UUID.cast(id) do
        {:ok, id} -> [id]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end
end
