defmodule Palee.Infrastructure.Fiscal.ConnectionCheckFields do
  @moduledoc """
  The columns a connection check may write (ADR-273), as an `update_all`
  `set:` list. Unknown keys are dropped, so a caller can never touch the
  credentials through it.
  """

  @fields ~w(status last_error error_code checked_at next_check_at check_failures)a

  def set(attrs) when is_map(attrs) do
    attrs
    |> Map.take(@fields)
    |> Enum.to_list()
  end
end
