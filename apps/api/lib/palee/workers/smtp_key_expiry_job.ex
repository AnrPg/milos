defmodule Palee.Workers.SmtpKeyExpiryJob do
  @moduledoc "Daily: warns before the SMTP key expires (ADR-212, `Application.SmtpKeyExpiryCheck`)."

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.SmtpKeyExpiryCheck

  @impl Oban.Worker
  def perform(_job) do
    {:ok, _result} = SmtpKeyExpiryCheck.call()
    :ok
  end
end
