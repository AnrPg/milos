defmodule Palee.Workers.HealthCertificateRemindersJob do
  @moduledoc """
  ADR-252: daily reminders before a client's health certificate expires,
  for every box that requires certificates. Idempotent per certificate and
  expiry date.
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3, unique: [period: 3_600]

  alias Palee.Application.Documents.HealthCertificateReminders

  @impl Oban.Worker
  def perform(_job) do
    HealthCertificateReminders.remind_all()
    :ok
  end
end
