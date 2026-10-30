defmodule Palee.Infrastructure.Partners.EctoVerificationStore do
  @moduledoc """
  Ecto adapter of the Partners verification store (ADR-280). Runs inside
  the session the facade opened; row security limits every query to what
  that person (or vendor, or system) may see. Reads of other people go
  through the migration's definer functions only.
  """

  @behaviour Palee.Partners.Ports.VerificationStore

  import Ecto.Query

  alias Palee.Partners.{PhoneCode, SponsorLink, Sponsorship, Verification, VerificationRequest}
  alias Palee.Repo

  @impl true
  def transaction(fun) do
    Repo.transaction(fn ->
      case fun.() do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
        other -> other
      end
    end)
  end

  # -- verifications -------------------------------------------------------------

  @impl true
  def get_verification(user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, user_id} -> Repo.get_by(Verification, user_id: user_id)
      :error -> nil
    end
  end

  @impl true
  def verify_by_membership do
    case Repo.query!("SELECT (palee_partner_verify_by_membership()).id") do
      %{rows: [[nil]]} -> nil
      %{rows: [[id]]} -> Repo.get(Verification, Ecto.UUID.load!(id))
      _none -> nil
    end
  end

  @impl true
  def verification_badges([]), do: %{}

  def verification_badges(ids) do
    %{rows: rows} =
      Repo.query!(
        "SELECT user_id, method, box_name FROM palee_partner_verification_badges($1)",
        [dump_ids(ids)]
      )

    Map.new(rows, fn [user_id, method, box_name] ->
      {Ecto.UUID.load!(user_id), %{method: method, box_name: box_name}}
    end)
  end

  @impl true
  def sponsor_standing([], _since), do: %{}

  def sponsor_standing(ids, since) do
    %{rows: rows} =
      Repo.query!(
        "SELECT user_id, method, status, penalty_until, vouches FROM palee_partner_sponsor_standing($1, $2)",
        [dump_ids(ids), since]
      )

    Map.new(rows, fn [user_id, method, status, penalty_until, vouches] ->
      {Ecto.UUID.load!(user_id),
       %{method: method, status: status, penalty_until: penalty_until, vouches: vouches}}
    end)
  end

  @impl true
  def insert_verification(attrs), do: attrs |> Verification.changeset() |> Repo.insert()

  @impl true
  def update_verification(%Verification{} = verification, changes),
    do: verification |> Verification.changeset(changes) |> Repo.update()

  @impl true
  def list_verifications([]), do: []

  def list_verifications(ids),
    do: Verification |> where([v], v.user_id in ^ids) |> Repo.all()

  # -- requests ------------------------------------------------------------------

  @impl true
  def get_request(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(VerificationRequest, id)
      :error -> nil
    end
  end

  @impl true
  def latest_request(user_id) do
    VerificationRequest
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc: r.inserted_at, desc: r.id)
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def create_request(attrs) do
    attrs
    |> VerificationRequest.changeset()
    |> Repo.insert()
    |> request_result()
  end

  @impl true
  def update_request(%VerificationRequest{} = request, changes) do
    request
    |> VerificationRequest.changeset(changes)
    |> Repo.update()
    |> request_result()
  end

  defp request_result({:ok, request}), do: {:ok, request}

  defp request_result({:error, %Ecto.Changeset{errors: errors} = changeset}) do
    cond do
      Keyword.has_key?(errors, :phone_hash) -> {:error, :partner_phone_taken}
      Keyword.has_key?(errors, :user_id) -> {:error, :partner_verification_request_open}
      true -> {:error, changeset}
    end
  end

  @impl true
  def list_requests(status, limit) do
    VerificationRequest
    |> where([r], r.status == ^status)
    |> order_by([r], asc_nulls_last: r.submitted_at, asc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @impl true
  def requests_with_selfies_before(cutoff) do
    VerificationRequest
    |> where([r], r.status == "in_review" and r.selfie_uploaded_at <= ^cutoff)
    |> Repo.all()
  end

  @impl true
  def requests_of(user_id),
    do: VerificationRequest |> where([r], r.user_id == ^user_id) |> Repo.all()

  # -- phone codes ---------------------------------------------------------------

  @impl true
  def count_codes_since(user_id, since) do
    PhoneCode
    |> where([c], c.user_id == ^user_id and c.sent_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def insert_code(attrs), do: attrs |> PhoneCode.changeset() |> Repo.insert()

  @impl true
  def latest_code(request_id) do
    PhoneCode
    |> where([c], c.request_id == ^request_id)
    |> order_by([c], desc: c.sent_at, desc: c.id)
    |> limit(1)
    |> Repo.one()
  end

  @impl true
  def update_code(%PhoneCode{} = code, changes),
    do: code |> PhoneCode.changeset(changes) |> Repo.update()

  @impl true
  def delete_code(%PhoneCode{} = code) do
    Repo.delete_all(where(PhoneCode, [c], c.id == ^code.id))
    :ok
  end

  @impl true
  def delete_codes_before(cutoff) do
    {count, _rows} = PhoneCode |> where([c], c.sent_at < ^cutoff) |> Repo.delete_all()
    count
  end

  # -- sponsorships --------------------------------------------------------------

  @impl true
  def get_sponsorship(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(Sponsorship, id)
      :error -> nil
    end
  end

  @impl true
  def sponsorship_between(candidate_id, sponsor_id),
    do: Repo.get_by(Sponsorship, candidate_id: candidate_id, sponsor_id: sponsor_id)

  @impl true
  def sponsorships_of_candidate(candidate_id) do
    Sponsorship
    |> where([s], s.candidate_id == ^candidate_id)
    |> order_by([s], asc: s.requested_at, asc: s.id)
    |> Repo.all()
  end

  @impl true
  def sponsorships_of_sponsor(sponsor_id, statuses) do
    Sponsorship
    |> where([s], s.sponsor_id == ^sponsor_id and s.status in ^statuses)
    |> order_by([s], desc: s.requested_at, desc: s.id)
    |> Repo.all()
  end

  @impl true
  def count_vouches_since(sponsor_id, since) do
    Sponsorship
    |> where([s], s.sponsor_id == ^sponsor_id and s.status == "vouched" and s.decided_at >= ^since)
    |> Repo.aggregate(:count)
  end

  @impl true
  def insert_sponsorship(attrs) do
    case attrs |> Sponsorship.changeset() |> Repo.insert() do
      {:ok, sponsorship} ->
        {:ok, sponsorship}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if Keyword.has_key?(errors, :candidate_id),
          do: {:error, :partner_sponsor_already_asked},
          else: {:error, changeset}
    end
  end

  @impl true
  def update_sponsorship(%Sponsorship{} = sponsorship, changes),
    do: sponsorship |> Sponsorship.changeset(changes) |> Repo.update()

  @impl true
  def delete_open_sponsorships(candidate_id) do
    {count, _rows} =
      Sponsorship
      |> where([s], s.candidate_id == ^candidate_id and s.status == "requested")
      |> Repo.delete_all()

    count
  end

  @impl true
  def vouched_sponsor_ids(candidate_id) do
    Sponsorship
    |> where([s], s.candidate_id == ^candidate_id and s.status == "vouched")
    |> select([s], s.sponsor_id)
    |> Repo.all()
  end

  # -- links ---------------------------------------------------------------------

  @impl true
  def insert_link(attrs), do: attrs |> SponsorLink.changeset() |> Repo.insert()

  @impl true
  def delete_links(candidate_id) do
    {count, _rows} =
      SponsorLink |> where([l], l.candidate_id == ^candidate_id) |> Repo.delete_all()

    count
  end

  @impl true
  def find_link(digest) do
    case Repo.query!(
           "SELECT id, candidate_id, expires_at, used_at FROM palee_partner_sponsor_link($1)",
           [digest]
         ) do
      %{rows: [[id, candidate_id, expires_at, used_at] | _rest]} ->
        %{
          id: Ecto.UUID.load!(id),
          candidate_id: Ecto.UUID.load!(candidate_id),
          expires_at: expires_at,
          used_at: used_at
        }

      _none ->
        nil
    end
  end

  @impl true
  def redeem_link(digest, now) do
    case Repo.query!("SELECT palee_partner_redeem_sponsor_link($1, $2)", [digest, now]) do
      %{rows: [[id]]} when is_binary(id) -> Ecto.UUID.load!(id)
      _none -> nil
    end
  end

  # -- account deletion ----------------------------------------------------------

  @impl true
  def purge_person(user_id) do
    {:ok, keys} =
      Repo.transaction(fn ->
        keys =
          VerificationRequest
          |> where([r], r.user_id == ^user_id and not is_nil(r.selfie_key))
          |> select([r], r.selfie_key)
          |> Repo.all()

        Repo.delete_all(where(PhoneCode, [c], c.user_id == ^user_id))
        Repo.delete_all(where(VerificationRequest, [r], r.user_id == ^user_id))

        Repo.delete_all(
          where(Sponsorship, [s], s.candidate_id == ^user_id or s.sponsor_id == ^user_id)
        )

        Repo.delete_all(where(SponsorLink, [l], l.candidate_id == ^user_id))

        Repo.update_all(where(SponsorLink, [l], l.used_by_id == ^user_id),
          set: [used_by_id: nil]
        )

        Repo.delete_all(where(Verification, [v], v.user_id == ^user_id))
        keys
      end)

    keys
  end

  defp dump_ids(ids), do: ids |> Enum.uniq() |> Enum.map(&Ecto.UUID.dump!/1)
end
