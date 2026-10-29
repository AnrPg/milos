defmodule Palee.Notifications.PushConfig do
  @moduledoc """
  The Web Push key pair and contact in use (ADR-275).

  Keys given to the server (`WEB_PUSH_PUBLIC_KEY` / `WEB_PUSH_PRIVATE_KEY`,
  `config :palee, :web_push_server_keys`) win. Otherwise Palee uses the pair it
  stores, and makes one on first use when none is stored
  (`config :palee, :web_push_auto_keys`). The contact is the server's
  `WEB_PUSH_SUBJECT`, else the one saved in the platform console, else
  `config :palee, :web_push_default_subject`.
  """

  alias Palee.Notifications.Domain.VapidKeys
  alias Palee.Notifications.PushKeyStore

  @type source :: :server | :palee | :none
  @type t :: %{
          vapid_public_key: String.t() | nil,
          vapid_private_key: String.t() | nil,
          vapid_subject: String.t() | nil,
          source: source(),
          keys_created_at: DateTime.t() | nil
        }

  @spec enabled?() :: boolean()
  def enabled?, do: ready?(config())

  def public_key, do: config().vapid_public_key

  @spec ready?(t()) :: boolean()
  def ready?(config) do
    Enum.all?(
      [config.vapid_public_key, config.vapid_private_key, config.vapid_subject],
      &present?/1
    )
  end

  @spec config() :: t()
  def config do
    case server_keys() do
      %{public_key: public, private_key: private, subject: subject} ->
        %{
          vapid_public_key: public,
          vapid_private_key: private,
          vapid_subject: subject || stored_subject() || default_subject(),
          source: :server,
          keys_created_at: nil
        }

      nil ->
        stored = stored_keys()

        %{
          vapid_public_key: stored[:vapid_public_key],
          vapid_private_key: stored[:vapid_private_key],
          vapid_subject: present_or_nil(stored[:vapid_subject]) || default_subject(),
          source: if(present?(stored[:vapid_private_key]), do: :palee, else: :none),
          keys_created_at: stored[:keys_created_at]
        }
    end
  end

  @doc "Hands `config` to `web_push_elixir`, which reads the keys from its env."
  def apply_to_web_push_elixir(config \\ config()) do
    Application.put_env(:web_push_elixir, :vapid_public_key, config.vapid_public_key)
    Application.put_env(:web_push_elixir, :vapid_private_key, config.vapid_private_key)
    Application.put_env(:web_push_elixir, :vapid_subject, config.vapid_subject)
    :ok
  end

  def auto_keys?, do: Application.get_env(:palee, :web_push_auto_keys, true) == true

  defp server_keys do
    keys = Application.get_env(:palee, :web_push_server_keys, [])
    public = present_or_nil(keys[:public_key])
    private = present_or_nil(keys[:private_key])

    if public && private,
      do: %{public_key: public, private_key: private, subject: present_or_nil(keys[:subject])}
  end

  defp stored_keys do
    stored = PushKeyStore.get()

    if auto_keys?() and
         not (present?(stored.vapid_public_key) and present?(stored.vapid_private_key)) do
      PushKeyStore.put_keys_if_missing(VapidKeys.generate())
    else
      stored
    end
  rescue
    _error -> %{}
  end

  defp stored_subject do
    present_or_nil(PushKeyStore.get().vapid_subject)
  rescue
    _error -> nil
  end

  defp default_subject, do: present_or_nil(Application.get_env(:palee, :web_push_default_subject))

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
  defp present_or_nil(value), do: if(present?(value), do: value)
end
