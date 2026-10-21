defmodule Palee.Widgets.Ports.WidgetTokenStore do
  @moduledoc "Persistence of the widget installs (ADR-173), inside the person's session."

  @callback create_widget_token(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback get_widget_token(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback delete_widget_token(Ecto.UUID.t(), Ecto.UUID.t()) :: boolean()
  @callback delete_widget_tokens_beyond(Ecto.UUID.t(), pos_integer()) :: non_neg_integer()
end
