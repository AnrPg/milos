defmodule MilosTraining.Places.HomeArea do
  @moduledoc "One neighbourhood of a person's «Η περιοχή μου»; position 0 is the main one (ADR-154)."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_home_areas" do
    field :user_id, :binary_id
    field :neighbourhood_id, :binary_id
    field :position, :integer

    timestamps(type: :utc_datetime_usec)
  end
end
