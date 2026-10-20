defmodule MilosTraining.DomainEvents.Handler do
  @moduledoc "A reaction to a domain event (see `MilosTraining.DomainEvents`)."

  @callback handle_event(MilosTraining.DomainEvents.name(), map()) :: any()
end
