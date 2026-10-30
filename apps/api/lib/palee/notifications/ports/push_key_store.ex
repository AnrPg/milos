defmodule Palee.Notifications.Ports.PushKeyStore do
  @moduledoc """
  Where the installation's Web Push key pair and contact live (ADR-277). One
  row for the whole platform; the private key is encrypted at rest.
  """

  @type stored :: %{
          vapid_public_key: String.t() | nil,
          vapid_private_key: String.t() | nil,
          vapid_subject: String.t() | nil,
          keys_created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc "The stored row, or empty values when nothing is stored yet."
  @callback get() :: stored()

  @doc """
  Stores `keys` only when no usable pair is stored (first start, or a pair the
  current encryption key can no longer read). Safe to race: the stored pair
  after the call is the one every caller gets back.
  """
  @callback put_keys_if_missing(Palee.Notifications.Domain.VapidKeys.t()) :: stored()

  @doc "Replaces the pair unconditionally."
  @callback replace_keys(Palee.Notifications.Domain.VapidKeys.t()) :: {:ok, stored()}

  @callback put_subject(String.t()) :: {:ok, stored()} | {:error, Ecto.Changeset.t()}

  @doc "Every browser subscription and the last delivered push (vendor only)."
  @callback device_stats() :: %{device_count: non_neg_integer(), last_sent_at: DateTime.t() | nil}

  @doc "Removes every browser subscription (vendor only); returns how many."
  @callback forget_all_devices() :: non_neg_integer()
end
