defmodule Palee.Imports.Ports.Clock do
  @moduledoc "The time imports read (ADR-254); tests fix it."

  @callback now() :: DateTime.t()
end
