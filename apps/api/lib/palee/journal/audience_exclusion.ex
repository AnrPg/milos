defmodule Palee.Journal.AudienceExclusion do
  @moduledoc "A coach the member left out of «Οι coach μου» by default (ADR-162)."

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "journal_coach_audience_exclusions" do
    field(:user_id, :binary_id, primary_key: true)
    field(:organization_id, :binary_id, primary_key: true)
    field(:coach_user_id, :binary_id, primary_key: true)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
