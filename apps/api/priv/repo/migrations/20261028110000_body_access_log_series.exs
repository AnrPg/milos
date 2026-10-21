defmodule Palee.Repo.Migrations.BodyAccessLogSeries do
  @moduledoc "ADR-158: a coach reading a client's metric series is logged too."
  use Ecto.Migration

  def up do
    drop constraint(:body_access_log, :body_access_log_subject_check)

    create constraint(:body_access_log, :body_access_log_subject_check,
             check: "subject IN ('list', 'snapshot', 'series')"
           )
  end

  def down do
    execute "DELETE FROM body_access_log WHERE subject = 'series'"
    drop constraint(:body_access_log, :body_access_log_subject_check)

    create constraint(:body_access_log, :body_access_log_subject_check,
             check: "subject IN ('list', 'snapshot')"
           )
  end
end
