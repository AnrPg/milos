defmodule Palee.Widgets.WidgetToken do
  @moduledoc """
  One app install that shows home-screen widgets (ADR-173). The widget holds
  a signed token naming this row; deleting the row (sign-out, a new token
  for the install) revokes it. Nothing else is stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @platforms ~w(ios android)

  schema "widget_tokens" do
    field :user_id, :binary_id
    field :platform, :string

    timestamps(type: :utc_datetime_usec)
  end

  def platforms, do: @platforms

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:user_id, :platform])
    |> validate_required([:user_id, :platform])
    |> validate_inclusion(:platform, @platforms)
    |> check_constraint(:platform, name: :widget_tokens_platform_check)
  end
end
