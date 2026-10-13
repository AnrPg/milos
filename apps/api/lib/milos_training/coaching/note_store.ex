defmodule MilosTraining.Coaching.NoteStore do
  @moduledoc false
  @behaviour MilosTraining.Coaching.Ports.NoteStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :coaching_note_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def create(context, attrs), do: tenant_call(context, :create, [attrs])
  @impl true
  def get(context, id), do: tenant_call(context, :get, [id])
  @impl true
  def update(context, id, attrs), do: tenant_call(context, :update, [id, attrs])
  @impl true
  def delete(context, id), do: tenant_call(context, :delete, [id])
  @impl true
  def list_for_client(context, client_id), do: tenant_call(context, :list_for_client, [client_id])

  @impl true
  def record_reads(context, note_ids, reader_id, at),
    do: tenant_call(context, :record_reads, [note_ids, reader_id, at])

  @impl true
  def list_reads(context, coach_id), do: tenant_call(context, :list_reads, [coach_id])
end
