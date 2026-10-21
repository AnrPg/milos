defmodule Palee.Coaching.FormReviewStore do
  @moduledoc false
  @behaviour Palee.Coaching.Ports.FormReviewStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:palee, :coaching_form_review_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def create_review(context, attrs), do: tenant_call(context, :create_review, [attrs])

  @impl true
  def get_review(context, id), do: tenant_call(context, :get_review, [id])

  @impl true
  def list_reviews(context, filters), do: tenant_call(context, :list_reviews, [filters])

  @impl true
  def review(context, id, attrs), do: tenant_call(context, :review, [id, attrs])

  @impl true
  def withdraw(context, id), do: tenant_call(context, :withdraw, [id])

  @impl true
  def alerted_message_ids(context, message_ids),
    do: tenant_call(context, :alerted_message_ids, [message_ids])

  @impl true
  def record_alert(context, attrs), do: tenant_call(context, :record_alert, [attrs])
end
