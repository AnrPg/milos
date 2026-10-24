defmodule Palee.Notifications.NotificationPreference do
  @moduledoc """
  One stored choice of a person (ADR-199): whether `category` reaches them
  on `channel`. Only choices that differ from the default are kept.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "notification_preferences" do
    field :user_id, :binary_id, primary_key: true
    field :category, :string, primary_key: true
    field :channel, :string, primary_key: true
    field :enabled, :boolean

    timestamps(type: :utc_datetime_usec)
  end
end
