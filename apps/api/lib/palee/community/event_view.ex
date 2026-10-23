defmodule Palee.Community.EventViewDay do
  @moduledoc """
  How often an event's page was opened on a day and by how many distinct
  people (ADR-185 §7, Αναλυτικά). Aggregated only: no viewer is stored.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "community_event_view_days" do
    field :organization_id, :binary_id
    field :event_id, :binary_id, primary_key: true
    field :day, :date, primary_key: true
    field :views, :integer, default: 0
    field :viewers, :integer, default: 0
  end
end

defmodule Palee.Community.EventViewMark do
  @moduledoc """
  Dedupes a viewer within one day (ADR-185 §7): an HMAC of the event, the
  day and the viewer under a server key. It cannot be joined to a person
  or across events and days, and is dropped once the day is over.
  """

  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "community_event_view_marks" do
    field :organization_id, :binary_id
    field :event_id, :binary_id, primary_key: true
    field :day, :date, primary_key: true
    field :viewer_key, :binary, primary_key: true
  end
end
