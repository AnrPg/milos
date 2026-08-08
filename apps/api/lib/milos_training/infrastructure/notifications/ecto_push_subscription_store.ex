defmodule MilosTraining.Infrastructure.Notifications.EctoPushSubscriptionStore do
  @behaviour MilosTraining.Notifications.Ports.PushSubscriptionStore

  import Ecto.Query

  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Notifications.PushSubscription
  alias MilosTraining.Repo

  @impl true
  def save_push_subscription(params) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    endpoint = Map.get(params, :endpoint) || Map.get(params, "endpoint")

    existing_subscription = Repo.get_by(PushSubscription, endpoint: endpoint)
    scoped_existing? = existing_subscription && existing_subscription.user_id == current_user_id()

    if existing_subscription && existing_subscription.user_id != current_user_id() do
      {:error, :push_subscription_endpoint_in_use}
    else
      changeset =
        %PushSubscription{}
        |> PushSubscription.changeset(params)

      Repo.insert(changeset,
        on_conflict: [
          set: [
            p256dh_key: Ecto.Changeset.get_field(changeset, :p256dh_key),
            auth_key: Ecto.Changeset.get_field(changeset, :auth_key),
            expiration_time: Ecto.Changeset.get_field(changeset, :expiration_time),
            updated_at: now
          ]
        ],
        conflict_target: :endpoint,
        returning: true
      )
    end
    |> case do
      {:ok, %PushSubscription{} = subscription} ->
        {:ok, normalize_subscription(subscription),
         if(scoped_existing?, do: :updated, else: :created)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @impl true
  def list_push_subscriptions(user_id) do
    PushSubscription
    |> scoped_to_user()
    |> where([subscription], subscription.user_id == ^user_id)
    |> order_by([subscription], desc: subscription.updated_at)
    |> Repo.all()
    |> Enum.map(&normalize_subscription/1)
  end

  @impl true
  def get_push_subscription(user_id, endpoint) do
    PushSubscription
    |> scoped_to_user()
    |> where(
      [subscription],
      subscription.user_id == ^user_id and subscription.endpoint == ^endpoint
    )
    |> Repo.one()
    |> case do
      %PushSubscription{} = subscription -> normalize_subscription(subscription)
      nil -> nil
    end
  end

  @impl true
  def delete_push_subscription(user_id, endpoint) do
    PushSubscription
    |> scoped_to_user()
    |> where(
      [subscription],
      subscription.user_id == ^user_id and subscription.endpoint == ^endpoint
    )
    |> Repo.delete_all()
    |> elem(0)
    |> Kernel.>(0)
  end

  defp normalize_subscription(%PushSubscription{} = subscription) do
    %{
      id: subscription.id,
      user_id: subscription.user_id,
      endpoint: subscription.endpoint,
      expiration_time: subscription.expiration_time,
      keys: %{
        "p256dh" => subscription.p256dh_key,
        "auth" => subscription.auth_key
      },
      inserted_at: subscription.inserted_at,
      updated_at: subscription.updated_at
    }
  end

  defp scoped_to_user(query) do
    case RepoContext.current_setting("app.user_id") do
      user_id when is_binary(user_id) -> where(query, [row], row.user_id == ^user_id)
      _missing_scope -> where(query, [row], false)
    end
  end

  defp current_user_id, do: RepoContext.current_setting("app.user_id")
end
