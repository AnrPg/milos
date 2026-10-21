defmodule Palee.Application.Ports.MapLinkResolver do
  @moduledoc "Follows a short map link (e.g. maps.app.goo.gl) to the long URL it stands for."

  @callback expand(String.t()) :: {:ok, String.t()} | {:error, term()}
end
