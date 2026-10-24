defmodule Palee.Guides.GuideProgress do
  @moduledoc "How far one person got in one in-app walkthrough (ADR-193)."

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "guide_progress" do
    field :user_id, :binary_id, primary_key: true
    field :guide_id, :string, primary_key: true
    field :version, :integer
    field :status, :string
    field :step, :integer, default: 0
    field :runs, :integer, default: 1
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end
end
