defmodule Palee.Application.PartnerVerificationRetention do
  @moduledoc """
  What Partners verification keeps, and for how long (ADR-280 §3):

  - `run/1` (daily, `Palee.Workers.PartnerVerificationRetention`): a
    request in review whose selfie is 7 days old is not decided by then:
    the selfie is deleted, the request becomes `expired` and the person is
    told to take a new one; SMS codes older than a day are deleted.
  - `purge_person/1` (account deletion, ADR-211): the person's selfies and
    every verification row of theirs go.

  Both run as the system (no acting person).
  """

  require Logger

  alias Palee.Application.{PartnerSelfieStorage, PartnerVerificationNotices}
  alias Palee.Partners.Verifications

  @doc "Expires unreviewed selfies past retention and deletes old codes."
  def run(now \\ DateTime.utc_now()) do
    expired =
      :system
      |> Verifications.requests_with_selfies_before(Verifications.selfie_retention_cutoff(now))
      |> Enum.count(&(expire(&1, now) == :ok))

    codes = Verifications.delete_codes_before(:system, Verifications.code_retention_cutoff(now))
    %{expired_requests: expired, deleted_codes: codes}
  end

  defp expire(request, now) do
    if Verifications.selfie_expired?(request, now) do
      case Verifications.update_request(:system, request, Verifications.expire_changes()) do
        {:ok, expired} ->
          PartnerSelfieStorage.delete_under(request.user_id, request.id)
          PartnerVerificationNotices.decided(expired, "expired")
          :ok

        {:error, reason} ->
          Logger.warning("partner_verification_expire_failed reason=#{inspect(reason)}")
          :error
      end
    else
      :skipped
    end
  end

  @doc "Deletes the person's selfies and verification rows (account deletion)."
  def purge_person(user_id) when is_binary(user_id) do
    keys = Verifications.purge_person(:system, user_id)
    PartnerSelfieStorage.delete(user_id, keys)
    # Uploads never submitted have no row; everything under the prefix goes.
    PartnerSelfieStorage.delete_under(user_id, :all)
  end
end
