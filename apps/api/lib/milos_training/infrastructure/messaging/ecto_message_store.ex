defmodule MilosTraining.Infrastructure.Messaging.EctoMessageStore do
  @behaviour MilosTraining.Messaging.Ports.MessageStore

  import Ecto.Query

  alias MilosTraining.Messaging.Message
  alias MilosTraining.Repo

  @default_limit 50

  @impl true
  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  @impl true
  def list_messages(thread_id, params) do
    limit = Map.get(params, :limit, @default_limit)
    before_id = Map.get(params, :before_id)

    Message
    |> where([m], m.thread_id == ^thread_id)
    |> maybe_before(before_id)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
  end

  @impl true
  def get_message(id) do
    Repo.get(Message, id)
  end

  defp maybe_before(query, nil), do: query

  defp maybe_before(query, before_id) do
    message = Repo.get(Message, before_id)

    if message do
      where(query, [m], m.inserted_at < ^message.inserted_at)
    else
      query
    end
  end
end
