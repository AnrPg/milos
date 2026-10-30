defmodule Palee.Workers.PartnerVerificationRetention do
  @moduledoc """
  ADR-280 §3, daily: selfies of the Partners check that waited 7 days
  without a decision are deleted (the request becomes `expired` and the
  person is told to take a new one), and SMS codes older than a day go
  (`Application.PartnerVerificationRetention.run/1`).
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  require Logger

  alias Palee.Application.PartnerVerificationRetention

  @impl Oban.Worker
  def perform(_job) do
    %{expired_requests: expired, deleted_codes: codes} = PartnerVerificationRetention.run()
    Logger.info("partner_verification_retention expired=#{expired} codes=#{codes}")
    :ok
  end
end
