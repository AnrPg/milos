defmodule Palee.DomainEvents.Handler do
  @moduledoc "A reaction to a domain event (see `Palee.DomainEvents`)."

  @callback handle_event(Palee.DomainEvents.name(), map()) :: any()
end
