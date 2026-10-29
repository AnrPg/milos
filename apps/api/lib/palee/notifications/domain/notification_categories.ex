defmodule Palee.Notifications.Domain.NotificationCategories do
  @moduledoc """
  ADR-199: the one place that says which category every notification type
  belongs to, which delivery channels each category has and which are
  locked, and how a person's stored choices resolve to what is delivered.

  Categories are what a person switches in Εγώ › Ρυθμίσεις › Ειδοποιήσεις;
  channels are how a notification reaches them: `in_app` (the bell) and
  `push` (browser and store-app push). A push is made from the bell row, so
  a push is delivered only while the category's bell is on too. `email` is a
  known channel no category offers yet: the only emails sent today go to
  people outside the app (owner invitations, corporate invoices).

  A stored choice overrides the default; with none stored every channel is
  on, which is how notifications behaved before preferences existed. Locked
  categories (account and payments: security, billing, access) are always
  delivered and cannot be changed.
  """

  @channels ~w(in_app push email)

  # Order is the order of the switches in Ρυθμίσεις.
  @categories [
    %{
      id: "bookings",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(
        booking_approved booking_rejected booking_waitlist_promoted
        trial_accepted trial_declined trial_reminder trial_follow_up trial_class_cancelled
        appointment_booked appointment_cancelled class_cancelled
        season_confirmed season_declined season_cancelled
      )
    },
    %{
      id: "messages",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(
        chat_message person_message message_request box_message coaching_message athlete_message
      )
    },
    %{
      id: "community",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(
        follow_requested follow_accepted new_follower challenge_completed around_new_matches
        community_group_approved community_group_declined community_group_join_requested
        community_group_join_approved community_group_archive_warning
        community_club_join_requested community_club_join_approved community_squad_invited
        community_event_waitlist_promoted community_event_cancelled community_event_changed
        community_event_reminder community_event_guest_joined community_event_trial_offer
        community_event_message community_event_cohost_request community_event_cohost_answered
        referral_progress referral_reward
      )
    },
    %{
      id: "coach",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(
        workout_note workout_changed workout_deleted workout_rejected workout_moved
        workout_assigned workout_assignment_requested workout_completed review_submitted
        form_review_submitted form_review_completed coaching_reply_overdue
        nutrition_plan_updated coach_client_assigned coach_note_viewed coach_wellness_summary
        training_goal_updated
      )
    },
    %{
      id: "partners",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(
        partner_match partner_message buddy_invite buddy_accepted buddy_message
        buddy_weekly_summary support_request support_reply support_no_reply_nudge
      )
    },
    %{
      id: "journal",
      channels: ~w(in_app push),
      locked: false,
      audience: "everyone",
      types: ~w(water_reminder body_measure_reminder craving_follow_up device_sync_error)
    },
    %{
      id: "staff",
      channels: ~w(in_app push),
      locked: false,
      audience: "staff",
      types: ~w(
        booking_pending booking_timeout check_in_visitor member_leaving
        trial_requested trial_booked trial_cancelled season_requested class_workout_missing
        community_group_proposed community_report_created referral_review
        inventory_repair_needed inventory_stock_low inventory_digest
        shop_stock_low shop_order_placed payment_needs_attention
      )
    },
    %{
      id: "account",
      channels: ~w(in_app push),
      locked: true,
      audience: "everyone",
      types: ~w(
        invoice_issued payment_reminder payment_failed package_expiring
        subscription_expiring subscription_grace access_ended
        password_reset_requested password_reset_completed business_demo_idle
        email_key_expiring
        journal_export_ready
        shop_order_ready shop_order_reminder shop_order_cancelled shop_back_in_stock
      )
    }
  ]

  @by_id Map.new(@categories, &{&1.id, &1})
  @type_category for c <- @categories, type <- c.types, into: %{}, do: {type, c.id}

  @type category_id :: String.t()
  @type channel :: String.t()
  @type choice :: %{category: category_id(), channel: channel(), enabled: boolean()}

  def channels, do: @channels
  def category_ids, do: Enum.map(@categories, & &1.id)

  @doc "Every type with a category, for the exhaustiveness check."
  def mapped_types, do: Map.keys(@type_category)

  @doc "Types listed under more than one category (must be none)."
  def duplicated_types do
    @categories
    |> Enum.flat_map(& &1.types)
    |> Enum.frequencies()
    |> Enum.filter(fn {_type, count} -> count > 1 end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec category_for(atom() | String.t()) :: category_id() | nil
  def category_for(type) when is_atom(type), do: category_for(Atom.to_string(type))
  def category_for(type) when is_binary(type), do: Map.get(@type_category, type)

  @doc """
  Whether a notification of `type` goes out on `channel`, given the person's
  stored choices. A type without a category (never in practice: a test keeps
  the map exhaustive) and a channel its category does not offer stay as they
  were before preferences: delivered.
  """
  @spec delivers?([choice()], atom() | String.t(), channel()) :: boolean()
  def delivers?(choices, type, channel) do
    case category_for(type) do
      nil -> true
      id -> resolved(@by_id[id], choices) |> Map.get(channel, true)
    end
  end

  @doc "Every category with its channels as they apply now, in display order."
  @spec resolve([choice()]) :: [map()]
  def resolve(choices) do
    Enum.map(@categories, fn category ->
      %{
        category: category.id,
        locked: category.locked,
        audience: category.audience,
        channels: resolved(category, choices)
      }
    end)
  end

  @doc """
  Validates a change of one category: `%{"push" => false}` and the like.
  Answers the channel → enabled pairs to store.
  """
  @spec parse_change(String.t(), map()) ::
          {:ok, [{channel(), boolean()}]}
          | {:error, :unknown_category | :locked_category | :invalid_change}
  def parse_change(category_id, params) when is_map(params) do
    with {:ok, category} <- fetch(category_id),
         :ok <- unlocked(category) do
      pairs =
        Enum.flat_map(category.channels, fn channel ->
          case Map.get(params, channel, Map.get(params, safe_atom(channel))) do
            nil -> []
            value -> [{channel, value}]
          end
        end)

      if pairs != [] and Enum.all?(pairs, fn {_channel, value} -> is_boolean(value) end),
        do: {:ok, pairs},
        else: {:error, :invalid_change}
    end
  end

  def parse_change(_category_id, _params), do: {:error, :invalid_change}

  defp fetch(id) when is_binary(id) do
    case Map.fetch(@by_id, id) do
      {:ok, category} -> {:ok, category}
      :error -> {:error, :unknown_category}
    end
  end

  defp fetch(_id), do: {:error, :unknown_category}

  defp unlocked(%{locked: true}), do: {:error, :locked_category}
  defp unlocked(_category), do: :ok

  defp safe_atom("in_app"), do: :in_app
  defp safe_atom("push"), do: :push
  defp safe_atom("email"), do: :email

  # Locked: everything on. Otherwise stored choice or on; push needs the bell.
  defp resolved(%{locked: true, channels: channels}, _choices),
    do: Map.new(channels, &{&1, true})

  defp resolved(%{id: id, channels: channels}, choices) do
    stored =
      for %{category: ^id, channel: channel, enabled: enabled} <- choices,
          into: %{},
          do: {channel, enabled}

    values = Map.new(channels, &{&1, Map.get(stored, &1, true)})

    if Map.has_key?(values, "push") and Map.get(values, "in_app") == false,
      do: Map.put(values, "push", false),
      else: values
  end
end
