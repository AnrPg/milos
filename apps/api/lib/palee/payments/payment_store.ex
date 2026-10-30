defmodule Palee.Payments.PaymentStore do
  @moduledoc false
  @behaviour Palee.Payments.Ports.PaymentStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :payment_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def transaction(context, fun), do: tenant_call(context, :transaction, [fun])

  @impl true
  def get_account(context), do: tenant_call(context, :get_account, [])
  @impl true
  def get_account(context, id), do: tenant_call(context, :get_account, [id])
  @impl true
  def save_account(context, attrs), do: tenant_call(context, :save_account, [attrs])
  @impl true
  def set_account_status(context, id, status, error, now),
    do: tenant_call(context, :set_account_status, [id, status, error, now])

  @impl true
  def insert_intent(context, attrs), do: tenant_call(context, :insert_intent, [attrs])
  @impl true
  def get_intent(context, id), do: tenant_call(context, :get_intent, [id])
  @impl true
  def get_intent_by_key(context, key), do: tenant_call(context, :get_intent_by_key, [key])
  @impl true
  def get_intent_by_ref(context, provider, ref),
    do: tenant_call(context, :get_intent_by_ref, [provider, ref])

  @impl true
  def update_intent(context, id, changes), do: tenant_call(context, :update_intent, [id, changes])
  @impl true
  def claim_due(context, which, now, limit),
    do: tenant_call(context, :claim_due, [which, now, limit])

  @impl true
  def claim_fulfilments(context, which, now, limit),
    do: tenant_call(context, :claim_fulfilments, [which, now, limit])

  @impl true
  def list_intents(context, filters), do: tenant_call(context, :list_intents, [filters])
  @impl true
  def add_refunded(context, id, amount), do: tenant_call(context, :add_refunded, [id, amount])

  @impl true
  def upsert_method(context, attrs), do: tenant_call(context, :upsert_method, [attrs])
  @impl true
  def get_method(context, id), do: tenant_call(context, :get_method, [id])
  @impl true
  def list_methods(context, user_id), do: tenant_call(context, :list_methods, [user_id])
  @impl true
  def update_method(context, id, changes), do: tenant_call(context, :update_method, [id, changes])
  @impl true
  def clear_autopay(context, user_id, except),
    do: tenant_call(context, :clear_autopay, [user_id, except])

  @impl true
  def autopay_methods(context), do: tenant_call(context, :autopay_methods, [])

  @impl true
  def insert_refund(context, attrs), do: tenant_call(context, :insert_refund, [attrs])
  @impl true
  def get_refund_by_key(context, key), do: tenant_call(context, :get_refund_by_key, [key])
  @impl true
  def update_refund(context, id, changes), do: tenant_call(context, :update_refund, [id, changes])
  @impl true
  def list_refunds(context, intent_id), do: tenant_call(context, :list_refunds, [intent_id])

  @impl true
  def record_webhook_event(context, attrs),
    do: tenant_call(context, :record_webhook_event, [attrs])

  @impl true
  def finish_webhook_event(context, id, status, error, now),
    do: tenant_call(context, :finish_webhook_event, [id, status, error, now])
end
