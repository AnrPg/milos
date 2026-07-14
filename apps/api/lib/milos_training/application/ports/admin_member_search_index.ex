defmodule MilosTraining.Application.Ports.AdminMemberSearchIndex do
  @callback replace_documents([map()]) :: :ok | {:error, term()}
  @callback search(map()) :: {:ok, %{users: [map()], meta: map()}} | {:error, term()}
end
