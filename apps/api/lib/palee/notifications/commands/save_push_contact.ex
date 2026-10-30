defmodule Palee.Notifications.Commands.SavePushContact do
  @moduledoc """
  Saves the contact push services use to reach the Palee team (ADR-277). A
  `WEB_PUSH_SUBJECT` given to the server wins, so saving one here is refused.
  """

  alias Palee.Notifications.Domain.PushContact
  alias Palee.Notifications.PushKeyStore

  def call(subject) do
    with :ok <- not_managed_by_server(),
         {:ok, contact} <- PushContact.normalize(subject),
         {:ok, _stored} <- PushKeyStore.put_subject(contact) do
      :ok
    end
  end

  defp not_managed_by_server do
    server = Application.get_env(:palee, :web_push_server_keys, [])[:subject]

    if is_binary(server) and String.trim(server) != "",
      do: {:error, :push_managed_by_server},
      else: :ok
  end
end
