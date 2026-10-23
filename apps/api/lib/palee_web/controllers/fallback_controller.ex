defmodule PaleeWeb.FallbackController do
  use PaleeWeb, :controller

  # ADR-184: business accounts. `business_not_activated` is the one stable code
  # every going-live action of a demo business answers; the web shows it as
  # «Ενεργοποίηση από την ομάδα Palee» with the way to ask for it.
  @business_errors %{
    business_not_activated:
      {:forbidden, "The Palee team activates this business before it can go live"},
    business_account_exists: {:conflict, "You already have a business waiting for activation"},
    business_signup_closed:
      {:conflict, "Ask the Palee team to turn your account into a business account"},
    invalid_business_kind: {:unprocessable_entity, "Choose a gym or an independent coach"},
    invalid_business_request: {:unprocessable_entity, "Check the details of the request"},
    business_request_pending: {:conflict, "You already have a pending request of this kind"},
    business_request_closed: {:conflict, "This request was already answered"},
    invalid_activation_link:
      {:not_found, "This activation link isn't valid for the account you're signed in with"},
    business_already_active: {:conflict, "This business is already active"},
    invalid_activation_role: {:unprocessable_entity, "Choose owner or admin"},
    invalid_activation_lifetime:
      {:unprocessable_entity, "A link lasts between one hour and 30 days"},
    account_not_found: {:not_found, "No account matches"},
    unknown_demo_section: {:unprocessable_entity, "There is no demo data for this screen"},
    demo_source_not_deletable:
      {:internal_server_error, "A demo seeder wrote a table it cannot remove"}
  }

  def call(conn, {:error, reason}) when is_map_key(@business_errors, reason) do
    {status, message} = Map.fetch!(@business_errors, reason)

    conn
    |> put_status(status)
    |> json(%{code: to_string(reason), error: message})
  end

  # ADR-190: the e-shop.
  @shop_errors %{
    insufficient_stock: {:conflict, "Not enough stock"},
    invalid_product_transition: {:conflict, "The product can't move to that state"},
    invalid_product_status:
      {:unprocessable_entity, "Status must be draft, published or archived"},
    invalid_product_options: {:unprocessable_entity, "Up to two options, each with values"},
    invalid_option_values: {:unprocessable_entity, "Pick one value for every option"},
    options_in_use: {:conflict, "A variant still uses an option value you removed"},
    product_has_no_variants: {:unprocessable_entity, "Add at least one variant"},
    product_has_no_channel: {:unprocessable_entity, "Sell it in the app, at the desk, or both"},
    product_not_available: {:conflict, "This product isn't on sale here"},
    variant_not_found: {:not_found, "Product variant not found"},
    invalid_cart: {:unprocessable_entity, "The basket is empty or malformed"},
    invalid_quantity: {:unprocessable_entity, "Check the quantity"},
    adjustment_reason_required: {:unprocessable_entity, "An adjustment needs a reason"},
    same_location: {:unprocessable_entity, "A transfer needs two different branches"},
    currency_mismatch: {:unprocessable_entity, "Every item must be in the same currency"},
    per_person_limit_exceeded: {:conflict, "You've reached the limit for this product"},
    pickup_location_required: {:unprocessable_entity, "Choose where you'll pick it up"},
    pickup_location_not_available:
      {:unprocessable_entity, "That branch can't hand over this order"},
    invalid_payment_mode: {:unprocessable_entity, "Choose how you'll pay"},
    invalid_payment_method: {:unprocessable_entity, "Choose cash, card, transfer or other"},
    online_payment_unavailable: {:conflict, "Online card payment isn't available yet"},
    on_account_not_allowed: {:conflict, "Paying on your account isn't available"},
    idempotency_key_required: {:unprocessable_entity, "Send an idempotency key"},
    invalid_order_transition: {:conflict, "The order can't move to that state"},
    order_not_paid: {:conflict, "Record the payment before handing the order over"},
    order_paid_refund_first: {:conflict, "The order is paid: refund it instead"},
    order_not_payable: {:conflict, "This order can't be paid"},
    refund_exceeds_paid: {:unprocessable_entity, "That's more than was paid"},
    refund_exceeds_quantity: {:unprocessable_entity, "That's more than was bought"},
    refund_lines_required: {:unprocessable_entity, "Choose what is refunded"},
    order_line_not_found: {:not_found, "Order line not found"},
    invalid_refund_amount: {:unprocessable_entity, "Check the refund amount"},
    payment_not_found: {:conflict, "The order has no payment to refund"},
    payment_not_refundable: {:conflict, "This payment can't be refunded"},
    invoice_has_payments: {:conflict, "The invoice has payments"},
    invoice_not_found: {:not_found, "Invoice not found"},
    invalid_revenue_stream: {:unprocessable_entity, "Unknown revenue stream"},
    promotion_code_invalid: {:unprocessable_entity, "This code isn't valid"},
    promotion_code_expired: {:conflict, "This code has expired"},
    promotion_code_exhausted: {:conflict, "This code has been used up"},
    promotion_code_not_applicable: {:unprocessable_entity, "This code is for another product"},
    promotion_code_changed: {:conflict, "This code changed; check the basket again"},
    product_not_promotable: {:conflict, "Publish the product in the app before promoting it"},
    invalid_promotion_target: {:unprocessable_entity, "Choose where the post goes"}
  }

  def call(conn, {:error, reason}) when is_map_key(@shop_errors, reason) do
    {status, message} = Map.fetch!(@shop_errors, reason)

    conn
    |> put_status(status)
    |> json(%{code: to_string(reason), error: message})
  end

  def call(conn, {:error, {:insufficient_stock, at}}) when is_map(at) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "insufficient_stock", error: "Not enough stock", variant_id: at[:variant_id]})
  end

  def call(conn, {:error, {:payment_failed, reason, order}}) do
    conn
    |> put_status(:payment_required)
    |> json(%{
      code: "payment_failed",
      reason: to_string(reason),
      error: "The payment didn't go through; the order is kept unpaid",
      order_id: order.id
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "validation_failed",
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    })
  end

  # ADR-163: WOD goals or «τι ένιωσες» feedback outside the taxonomy.
  def call(conn, {:error, {:invalid_goals, details}}) when is_map(details) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_goals",
      error: "Check the muscles and qualities",
      errors: Map.new(details, fn {field, message} -> {to_string(field), [message]} end)
    })
  end

  def call(conn, {:error, errors}) when is_list(errors) do
    normalized_errors =
      errors
      |> Enum.group_by(fn {field, _message} -> to_string(field) end, fn {_field, message} ->
        message
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "validation_failed", errors: normalized_errors})
  end

  # ADR-140 §6: a coaching message needs an active coaching relationship;
  # a message from the box belongs to the gym's thread with the member.
  def call(conn, {:error, :no_coaching_relationship}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "no_coaching_relationship",
      error: "Only a coach with an active coaching relationship can send a coaching message"
    })
  end

  def call(conn, {:error, :box_message_outside_box_thread}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "box_message_outside_box_thread",
      error: "A message from the box is sent in the gym's thread with the member"
    })
  end

  # ADR-138: club and channel governance.
  def call(conn, {:error, :channel_not_optional}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "channel_not_optional",
      error: "Every member is in this channel; it cannot be joined or left"
    })
  end

  # ADR-154: Γύρω μου.
  def call(conn, {:error, :origin_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "origin_required",
      error: "Choose where to search from: your area, your position or a place"
    })
  end

  def call(conn, {:error, :place_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "place_not_found", error: "No place matches that name"})
  end

  def call(conn, {:error, :filter_alerts_unsupported}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "filter_alerts_unsupported", error: "Only Γύρω μου filters have alerts"})
  end

  def call(conn, {:error, :invalid_place_ref}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_place_ref", error: "That search result has expired; search again"})
  end

  def call(conn, {:error, :geocoder_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{code: "geocoder_unavailable", error: "Address search is unavailable right now"})
  end

  def call(conn, {:error, reason}) when reason in [:not_a_map_link, :map_link_unresolved] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: Atom.to_string(reason), error: "No map point could be read from this link"})
  end

  def call(conn, {:error, :invalid_provider_kind}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_provider_kind", error: "Provider kind must be gym or coach"})
  end

  def call(conn, {:error, :invalid_timezone}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_timezone", error: "Unknown time zone"})
  end

  def call(conn, {:error, :invalid_notify_level}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_notify_level", error: "Unknown notification level"})
  end

  def call(conn, {:error, :cannot_post_in_channel}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "cannot_post_in_channel", error: "You cannot post in this channel"})
  end

  # ADR-142: audiences and follows.
  def call(conn, {:error, :invalid_audience}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_audience", error: "You cannot post to this audience"})
  end

  def call(conn, {:error, :invalid_follow_target}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_follow_target", error: "This cannot be followed"})
  end

  def call(conn, {:error, :cannot_follow_self}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "cannot_follow_self", error: "You cannot follow yourself"})
  end

  def call(conn, {:error, :attachment_not_shareable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "attachment_not_shareable",
      error: "Only your own journal entries can be attached"
    })
  end

  def call(conn, {:error, :invalid_current_password}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_current_password", error: "Current password is incorrect"})
  end

  def call(conn, {:error, :invalid_password}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_password", error: "Password is incorrect"})
  end

  # ADR-187: password recovery.
  def call(conn, {:error, reason})
      when reason in [
             :invalid_reset_link,
             :expired_reset_link,
             :invalid_recovery_code,
             :weak_password,
             :claimed_by_other,
             :not_claimed
           ] do
    {status, message} =
      case reason do
        :invalid_reset_link ->
          {:unprocessable_entity, "This reset link is not valid"}

        :expired_reset_link ->
          {:gone, "This reset link has expired"}

        :invalid_recovery_code ->
          {:unprocessable_entity, "The account or recovery code is wrong"}

        :weak_password ->
          {:unprocessable_entity, "Password must have at least 4 characters besides spaces"}

        :claimed_by_other ->
          {:conflict, "Someone else is handling this request"}

        :not_claimed ->
          {:conflict, "You are not handling this request"}
      end

    conn
    |> put_status(status)
    |> json(%{code: Atom.to_string(reason), error: message})
  end

  # ADR-187: the email already holds profiles and the password is not theirs.
  # Only the count is disclosed, never which profiles.
  def call(conn, {:error, {:email_in_use, %{profile_count: count, profile_limit: limit}}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "email_in_use",
      error: "This email already has accounts",
      profile_count: count,
      profile_limit: limit,
      errors: %{"email" => ["already has accounts"]}
    })
  end

  def call(conn, {:error, {:profile_limit, %{profile_limit: limit}}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "profile_limit",
      error: "This email already has the most accounts allowed",
      profile_limit: limit
    })
  end

  def call(conn, {:error, :email_taken}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "email_in_use", error: "This email already has accounts"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    emit_auth_anomaly(:invalid_credentials)

    conn
    |> put_status(:unauthorized)
    |> json(%{code: "invalid_credentials", error: "Invalid credentials"})
  end

  def call(conn, {:error, :invalid_refresh_token}) do
    emit_auth_anomaly(:invalid_refresh_token)

    conn
    |> put_status(:unauthorized)
    |> json(%{code: "invalid_refresh_token", error: "Invalid refresh token"})
  end

  def call(conn, {:error, :invalid_token}) do
    emit_auth_anomaly(:invalid_token)

    conn
    |> put_status(:unauthorized)
    |> json(%{code: "invalid_token", error: "Invalid token"})
  end

  def call(conn, {:error, :token_issuance_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{code: "token_issuance_failed", error: "Authentication service unavailable"})
  end

  def call(conn, {:error, :registration_cleanup_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{code: "registration_cleanup_failed", error: "Registration could not be completed"})
  end

  def call(conn, {:error, :auth_dependency_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "auth_dependency_unavailable",
      error: "Authentication dependency unavailable"
    })
  end

  def call(conn, {:error, :rate_limiter_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{code: "rate_limiter_unavailable", error: "Rate limiter unavailable"})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "not_found", error: "Not found"})
  end

  def call(conn, {:error, :cannot_delete_self}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "cannot_delete_self", error: "You cannot delete your own account"})
  end

  def call(conn, {:error, :last_admin}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "last_admin", error: "At least one admin account must remain"})
  end

  def call(conn, {:error, :expected_source_revision_required}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "expected_source_revision_required",
      error: "Expected source revision is required"
    })
  end

  def call(conn, {:error, :request_id_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "request_id_required", error: "A stable request_id UUID is required"})
  end

  def call(conn, {:error, :push_subscription_endpoint_in_use}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "push_subscription_endpoint_in_use",
      error: "This browser push subscription belongs to another signed-in user"
    })
  end

  def call(conn, {:error, :credit_reversal_required}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "credit_reversal_required",
      error: "Reverse linked credit applications before reversing this payment"
    })
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: "bad_request", error: "Required parameter is missing or invalid"})
  end

  def call(conn, {:error, :organization_export_required}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "organization_export_required",
      error: "Export the organization's data first: Delete permanently, then Export"
    })
  end

  def call(conn, {:error, :user_has_restricted_history}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "user_has_restricted_history",
      error: "This user has protected history and cannot be permanently deleted"
    })
  end

  def call(conn, {:error, :invitation_email_mismatch}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "invitation_email_mismatch",
      error: "This invitation was issued to a different email address"
    })
  end

  def call(conn, {:error, :invalid_invitation}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "invalid_invitation", error: "Invitation is invalid or unavailable"})
  end

  def call(conn, {:error, :join_link_unavailable}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "join_link_unavailable", error: "This join link is not active"})
  end

  def call(conn, {:error, :membership_unavailable}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "membership_unavailable",
      error: "Your membership in this organization is not active. Contact the organization."
    })
  end

  def call(conn, {:error, :invalid_tour}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_tour", error: "Unknown product tour"})
  end

  def call(conn, {:error, :invalid_onboarding_action}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_onboarding_action", error: "Unknown onboarding action or step"})
  end

  def call(conn, {:error, :invalid_join_link}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_join_link", error: "Choose member or athlete and on or off"})
  end

  def call(conn, {:error, :stale_dsl_revision}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "stale_dsl_revision",
      error:
        "The Quick Text source changed in another editor. Reload before saving or publishing."
    })
  end

  def call(conn, {:error, {:dsl_warnings_require_acknowledgement, diagnostics}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "dsl_warnings_require_acknowledgement",
      error: "Review and acknowledge the Quick Text warnings before publishing.",
      diagnostics: Enum.map(diagnostics, &json_dsl_diagnostic/1)
    })
  end

  def call(conn, {:error, reason})
      when reason in [
             :invalid_canonical_workout,
             :missing_workout_title,
             :missing_workout_type,
             :invalid_sections,
             :empty_execution_sequence,
             :invalid_execution_timer_segment
           ] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: to_string(reason),
      error: "The canonical workout failed publication preflight."
    })
  end

  def call(conn, {:error, {:unknown_scale_level, slug}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "unknown_scale_level",
      error: "The workout references an inactive or unknown scale level.",
      params: %{slug: slug}
    })
  end

  def call(conn, {:error, {:class_type_replacement_required, future_class_count}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "class_type_replacement_required",
      error: "Future classes require a replacement class type",
      future_class_count: future_class_count,
      params: %{future_class_count: future_class_count}
    })
  end

  def call(conn, {:error, :invalid_class_type_replacement}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_class_type_replacement",
      error: "Replacement class type must be a different active type"
    })
  end

  def call(conn, {:error, :last_active_class_type}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "last_active_class_type",
      error: "At least one active class type must remain"
    })
  end

  def call(conn, {:error, :class_type_archived}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "class_type_archived",
      error: "Archived class types cannot be modified or selected"
    })
  end

  def call(conn, {:error, :class_type_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "class_type_not_found", error: "Class type is missing or archived"})
  end

  def call(conn, {:error, :self_conversation}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "self_conversation",
      error: "A direct conversation requires another participant"
    })
  end

  def call(conn, {:error, :invalid_message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_message",
      error: "Read pointers must reference a message in this thread"
    })
  end

  def call(conn, {:error, :invalid_avatar_upload}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_avatar_upload",
      error: "Use a JPG, JPEG, PNG, WebP, GIF, BMP, or AVIF image up to 5 MiB"
    })
  end

  def call(conn, {:error, :avatar_upload_missing}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "avatar_upload_missing",
      error: "The avatar upload was not found in storage. Upload the image again."
    })
  end

  def call(conn, {:error, :avatar_upload_unverified}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "avatar_upload_unverified",
      error: "Avatar storage rejected server verification for this upload."
    })
  end

  def call(conn, {:error, :unsupported_avatar_type}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "unsupported_avatar_type",
      error:
        "The uploaded file is not a supported image. Use JPG, JPEG, PNG, WebP, GIF, BMP, or AVIF."
    })
  end

  def call(conn, {:error, :avatar_upload_metadata_missing}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "avatar_upload_metadata_missing",
      error: "The uploaded avatar is missing storage size metadata. Upload the image again."
    })
  end

  def call(conn, {:error, {:avatar_too_large, byte_size}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "avatar_too_large",
      params: %{byte_size: byte_size, max_bytes: 5_242_880},
      error: "The uploaded avatar is larger than 5 MiB."
    })
  end

  def call(conn, {:error, :avatar_key_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "avatar_key_forbidden",
      error: "The avatar upload does not belong to the current user."
    })
  end

  def call(conn, {:error, :avatar_storage_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "avatar_storage_unavailable",
      error: "Avatar storage could not be reached for verification. Try again shortly."
    })
  end

  # ADR-121 tenant logo upload.
  def call(conn, {:error, :invalid_brand_logo_upload}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_brand_logo_upload",
      error: "Use a PNG, JPEG, or WebP logo up to 2 MiB."
    })
  end

  def call(conn, {:error, :brand_logo_upload_missing}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "brand_logo_upload_missing",
      error: "The logo upload was not found in storage. Upload the image again."
    })
  end

  def call(conn, {:error, :unsupported_brand_logo_type}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "unsupported_brand_logo_type",
      error: "The uploaded file is not a PNG, JPEG, or WebP image."
    })
  end

  def call(conn, {:error, {:brand_logo_too_large, byte_size}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "brand_logo_too_large",
      params: %{byte_size: byte_size, max_bytes: 2_097_152},
      error: "The uploaded logo is larger than 2 MiB."
    })
  end

  def call(conn, {:error, :brand_logo_key_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "brand_logo_key_forbidden",
      error: "The logo upload does not belong to this organization."
    })
  end

  def call(conn, {:error, :brand_logo_storage_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "brand_logo_storage_unavailable",
      error: "Logo storage could not be reached for verification. Try again shortly."
    })
  end

  def call(conn, {:error, :invalid_invoice_upload}) do
    emit_upload_rejection(:invalid_invoice_upload)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_invoice_upload",
      error: "Use a PDF, JPG, JPEG, PNG, or WebP invoice document up to 10 MiB."
    })
  end

  def call(conn, {:error, :unsupported_invoice_upload_type}) do
    emit_upload_rejection(:unsupported_invoice_upload_type)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "unsupported_invoice_upload_type",
      error: "Invoice uploads only allow PDF, JPG, JPEG, PNG, and WebP documents."
    })
  end

  def call(conn, {:error, :document_upload_missing}) do
    emit_upload_rejection(:document_upload_missing)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "document_upload_missing",
      error: "The invoice upload was not found in storage. Upload the document again."
    })
  end

  def call(conn, {:error, :document_upload_unverified}) do
    emit_upload_rejection(:document_upload_unverified)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "document_upload_unverified",
      error: "Storage rejected server verification for this invoice upload."
    })
  end

  def call(conn, {:error, :document_upload_content_type_mismatch}) do
    emit_upload_rejection(:document_upload_content_type_mismatch)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "document_upload_content_type_mismatch",
      error: "The uploaded invoice document does not match the requested content type."
    })
  end

  def call(conn, {:error, :document_upload_metadata_missing}) do
    emit_upload_rejection(:document_upload_metadata_missing)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "document_upload_metadata_missing",
      error: "The uploaded invoice document is missing storage metadata. Upload it again."
    })
  end

  def call(conn, {:error, {:document_too_large, byte_size}}) do
    emit_upload_rejection(:document_too_large)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "document_too_large",
      params: %{byte_size: byte_size, max_bytes: 10_485_760},
      error: "The uploaded invoice document is larger than 10 MiB."
    })
  end

  def call(conn, {:error, :invalid_execution_source}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_execution_source", error: "Invalid execution source"})
  end

  def call(conn, {:error, :stale_execution}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "stale_execution", error: "Execution progress changed on another client"})
  end

  def call(conn, {:error, :execution_source_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "execution_source_forbidden",
      error: "Workout execution source is not authorized"
    })
  end

  def call(conn, {:error, :execution_source_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "execution_source_mismatch",
      error: "Workout execution source does not match the workout"
    })
  end

  def call(conn, {:error, :completion_processing_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "completion_processing_unavailable",
      error: "Workout completion processing is temporarily unavailable"
    })
  end

  def call(conn, {:error, :invalid_training_log_source}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_training_log_source",
      error: "Training log source type or reference is invalid"
    })
  end

  def call(conn, {:error, :training_log_source_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "training_log_source_forbidden",
      error: "You cannot log a workout for this source"
    })
  end

  def call(conn, {:error, :training_log_source_not_started}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "training_log_source_not_started",
      error: "This class has not started yet"
    })
  end

  def call(conn, {:error, :training_log_already_counted}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "training_log_already_counted",
      error: "A completed workout execution already counts this workout"
    })
  end

  def call(conn, {:error, :training_log_source_already_logged}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "training_log_source_already_logged",
      error: "This workout has already been logged"
    })
  end

  def call(conn, {:error, :training_log_entry_voided}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "training_log_entry_voided",
      error: "Voided training log entries cannot be changed"
    })
  end

  def call(conn, {:error, :stale_training_log_entry}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "stale_training_log_entry",
      error: "This entry changed elsewhere. Reload before saving."
    })
  end

  def call(conn, {:error, :promotion_code_inactive}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "promotion_code_inactive", error: "Promotion code is inactive"})
  end

  def call(conn, {:error, :promotion_campaign_inactive}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "promotion_campaign_inactive", error: "Promotion campaign is inactive"})
  end

  def call(conn, {:error, :promotion_campaign_not_started}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "promotion_campaign_not_started",
      error: "Promotion campaign has not started"
    })
  end

  def call(conn, {:error, :promotion_campaign_expired}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "promotion_campaign_expired", error: "Promotion campaign has expired"})
  end

  def call(conn, {:error, :promotion_code_max_redemptions_reached}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "promotion_code_max_redemptions_reached",
      error: "Promotion code redemption limit reached"
    })
  end

  # ADR-096 package contract errors. `params` carry the catalog field or lock
  # path so clients can localize and focus the offending input.
  def call(conn, {:error, {:package_type_invariant_violated, path}}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "package_type_invariant_violated",
      "This value is defined by the package type",
      %{field: path}
    )
  end

  def call(conn, {:error, {:entitlement_not_available, field}}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "entitlement_not_available",
      "This benefit is not available yet",
      %{field: field}
    )
  end

  def call(conn, {:error, {:invalid_package_field, field, reason}}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "invalid_package_field",
      "Invalid package field value",
      %{field: field, reason: to_string(reason)}
    )
  end

  def call(conn, {:error, {:unknown_package_field, field}}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "unknown_package_field",
      "Unknown package field",
      %{field: field}
    )
  end

  def call(conn, {:error, {:package_rule_violated, rule, field}}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "package_rule_violated",
      "Package rule violated",
      %{rule: to_string(rule), field: field}
    )
  end

  def call(conn, {:error, :invalid_package_fields}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "invalid_package_field",
      "Invalid package fields",
      %{}
    )
  end

  def call(conn, {:error, :invalid_package_type}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "invalid_package_type",
      "Invalid package type",
      %{}
    )
  end

  def call(conn, {:error, :package_type_not_available}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "package_type_not_available",
      "This package type is not available yet",
      %{}
    )
  end

  def call(conn, {:error, :package_type_change_requires_copy}) do
    package_contract_error(
      conn,
      :conflict,
      "package_type_change_requires_copy",
      "A sold package cannot change type; create a copy instead",
      %{}
    )
  end

  def call(conn, {:error, :package_already_used}) do
    package_contract_error(
      conn,
      :conflict,
      "package_already_used",
      "This package can be used only once per person",
      %{}
    )
  end

  def call(conn, {:error, :package_new_members_only}) do
    package_contract_error(
      conn,
      :conflict,
      "package_new_members_only",
      "This package is only for new members",
      %{}
    )
  end

  def call(conn, {:error, :package_not_renewable}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "package_not_renewable",
      "This package does not renew",
      %{}
    )
  end

  def call(conn, {:error, :finance_class_type_not_included}) do
    package_contract_error(
      conn,
      :forbidden,
      "finance_class_type_not_included",
      "This class type is not included in the package",
      %{}
    )
  end

  def call(conn, {:error, :finance_class_type_not_included, details}) do
    package_contract_error(
      conn,
      :forbidden,
      "finance_class_type_not_included",
      "This class type is not included in the package",
      details
    )
  end

  def call(conn, {:error, :package_inactive}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "package_inactive", error: "Inactive packages cannot be assigned"})
  end

  def call(conn, {:error, {:package_replacement_required, role}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "package_replacement_required",
      error: "A replacement package is required for #{role} subscribers",
      role: role,
      params: %{role: role}
    })
  end

  def call(conn, {:error, :invalid_package_replacement}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_package_replacement",
      error: "Replacement packages must be different active packages"
    })
  end

  def call(conn, {:error, :package_retirement_reconciliation_required}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "package_retirement_reconciliation_required",
      error: "Current subscribers require package retirement reconciliation"
    })
  end

  def call(conn, {:error, :referral_program_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "referral_program_required", error: "A referral program is required"})
  end

  def call(conn, {:error, :referral_program_inactive}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "referral_program_inactive", error: "The referral program is inactive"})
  end

  def call(conn, {:error, :referral_user_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "referral_user_not_found", error: "Referral participant was not found"})
  end

  def call(conn, {:error, :referral_membership_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "referral_membership_required",
      error: "Referral events require the referred user's finance membership"
    })
  end

  def call(conn, {:error, :referral_referrer_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "referral_referrer_role_ineligible",
      error: "Referral referrer must be a member or athlete"
    })
  end

  def call(conn, {:error, :referral_referred_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "referral_referred_role_ineligible",
      error: "Referral recipient must be a member or athlete"
    })
  end

  def call(conn, {:error, :invalid_billing_period}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_billing_period", error: "Invalid billing period"})
  end

  def call(conn, {:error, :promotion_discount_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "promotion_discount_required", error: "Promotion discount value is required"})
  end

  def call(conn, {:error, :invalid_promotion_discount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_promotion_discount", error: "Promotion discount is invalid"})
  end

  def call(conn, {:error, :review_target_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "review_target_required",
      error: "Review target id is required for this target type"
    })
  end

  def call(conn, {:error, :review_target_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "review_target_not_found", error: "Review target was not found"})
  end

  def call(conn, {:error, :review_target_not_completed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "review_target_not_completed",
      error: "Review target must be completed before it can be reviewed"
    })
  end

  def call(conn, {:error, :review_target_must_be_global}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "review_target_must_be_global",
      error: "This review target type must not include a target id"
    })
  end

  def call(conn, {:error, :invalid_referral_status_transition}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "invalid_referral_status_transition",
      error: "Invalid referral status transition"
    })
  end

  def call(conn, {:error, :referral_event_not_approved}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "referral_event_not_approved",
      error: "Referral event must be approved before applying rewards"
    })
  end

  # Member referrals (ADR-156).
  def call(conn, {:error, :referral_code_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "referral_code_unavailable",
      error: "No invite code could be made; try again"
    })
  end

  def call(conn, {:error, :referrer_not_member}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "referrer_not_member", error: "The new inviter must be a member of the box"})
  end

  def call(conn, {:error, :self_referral}), do: call(conn, {:error, :self_referral_not_allowed})

  def call(conn, {:error, :referral_already_qualified}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "referral_already_qualified",
      error: "The invite already counted and can no longer move to another member"
    })
  end

  def call(conn, {:error, :referral_gift_already_applied}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "referral_gift_already_applied",
      error: "The friend's gift was already applied"
    })
  end

  def call(conn, {:error, :referral_no_friend_gift}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "referral_no_friend_gift", error: "The programme gives the friend nothing"})
  end

  def call(conn, {:error, :no_active_subscription}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "no_active_subscription",
      error: "The member has no active package with an end date to extend"
    })
  end

  def call(conn, {:error, :recipient_membership_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "recipient_membership_not_found",
      error:
        "Referral reward recipient needs a finance membership profile before credit can be applied"
    })
  end

  def call(conn, {:error, :injury_already_healed}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "injury_already_healed", error: "Injury report is already healed"})
  end

  def call(conn, {:error, :injury_healed_before_started}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "injury_healed_before_started",
      error: "Healed date cannot be before started date"
    })
  end

  def call(conn, {:error, :injury_target_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "injury_target_role_ineligible",
      error: "Injury reports can only target members or athletes"
    })
  end

  def call(conn, {:error, :invalid_credit_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_credit_amount", error: "Credit amount must be greater than zero"})
  end

  def call(conn, {:error, :invalid_referral_reward_type}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_referral_reward_type", error: "Referral reward type is invalid"})
  end

  def call(conn, {:error, :insufficient_credit_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "insufficient_credit_balance", error: "Insufficient credit balance"})
  end

  def call(conn, {:error, :credit_exceeds_payment_amount}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "credit_exceeds_payment_amount",
      error: "Credit exceeds remaining payment amount"
    })
  end

  def call(conn, {:error, :payment_not_creditable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "payment_not_creditable",
      error: "Credit can only be applied to paid or pending payments"
    })
  end

  def call(conn, {:error, :payment_not_reversible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "payment_not_reversible",
      error: "Only paid or waived payments can be reversed"
    })
  end

  def call(conn, {:error, :invalid_payment_reversal_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_payment_reversal_amount",
      error: "Payment reversal amount must be greater than zero"
    })
  end

  def call(conn, {:error, :payment_reversal_exceeds_payment_amount}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "payment_reversal_exceeds_payment_amount",
      error: "Payment reversal exceeds remaining payment amount"
    })
  end

  def call(conn, {:error, :credit_entry_not_reversible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "credit_entry_not_reversible",
      error: "Only applied credit entries can be reversed"
    })
  end

  def call(conn, {:error, :credit_reversal_exceeds_application}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "credit_reversal_exceeds_application",
      error: "Credit reversal exceeds remaining applied credit"
    })
  end

  def call(conn, {:error, :credit_exceeds_invoice_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "credit_exceeds_invoice_balance",
      error: "Credit exceeds remaining invoice balance"
    })
  end

  def call(conn, {:error, :invoice_not_issued}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "invoice_not_issued",
      error: "Invoice must be issued before allocations can be applied"
    })
  end

  def call(conn, {:error, :invoice_already_paid}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "invoice_already_paid", error: "Invoice is already paid"})
  end

  def call(conn, {:error, :invoice_void}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "invoice_void", error: "Invoice is void"})
  end

  def call(conn, {:error, :invoice_has_allocations}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "invoice_has_allocations",
      error: "Invoice has payments or credits and cannot be voided"
    })
  end

  def call(conn, {:error, :role_ceiling_exceeded}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "role_ceiling_exceeded",
      error: "You cannot invite someone to a role more privileged than your own"
    })
  end

  def call(conn, {:error, :finance_entitlement_blocked}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "finance_entitlement_blocked", error: "Finance entitlement blocked"})
  end

  def call(conn, {:error, :finance_profile_missing}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "finance_profile_missing", error: "Finance profile required"})
  end

  def call(conn, {:error, :finance_entitlement_plan_missing}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_entitlement_plan_missing",
      error: "The active package has no enforceable entitlement plan"
    })
  end

  def call(conn, {:error, :finance_channel_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_channel_not_included",
      error: "Package channel not included",
      params: %{channel: "the required service"}
    })
  end

  def call(conn, {:error, :finance_channel_not_included, details}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_channel_not_included",
      error: "Package channel not included",
      params: details
    })
  end

  def call(conn, {:error, :finance_capability_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_capability_not_included",
      error: "Package capability not included",
      params: %{capability: "the required benefit"}
    })
  end

  def call(conn, {:error, :finance_capability_not_included, details}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_capability_not_included",
      error: "Package capability not included",
      params: details
    })
  end

  def call(conn, {:error, :finance_allowance_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_allowance_not_included",
      error: "Package allowance not included",
      params: %{allowance: "the required usage"}
    })
  end

  def call(conn, {:error, :finance_allowance_not_included, details}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "finance_allowance_not_included",
      error: "Package allowance not included",
      params: details
    })
  end

  def call(conn, {:error, :finance_allowance_exhausted, details}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "finance_allowance_exhausted",
      error: "Package allowance exhausted",
      params: details
    })
  end

  def call(conn, {:error, :invalid_allowance_grant}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_allowance_grant",
      error: "Allowance extension is invalid"
    })
  end

  def call(conn, {:error, :allowance_grant_already_revoked}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "allowance_grant_already_revoked",
      error: "Allowance extension is already revoked"
    })
  end

  def call(conn, {:error, {:invalid_backfill_package, role, reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_backfill_package",
      error: "Backfill package is missing or has an invalid entitlement contract",
      params: %{role: role, reason: inspect(reason)}
    })
  end

  def call(conn, {:error, :finance_entitlement_inactive}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "finance_entitlement_inactive", error: "Finance entitlement inactive"})
  end

  def call(conn, {:error, :payment_exceeds_invoice_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "payment_exceeds_invoice_balance",
      error: "Payment exceeds remaining invoice balance"
    })
  end

  def call(conn, {:error, :invalid_payment_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_payment_amount", error: "Payment amount must be greater than zero"})
  end

  def call(conn, {:error, :duplicate_renewal_invoice}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "duplicate_renewal_invoice",
      error: "Renewal invoice already exists for this service period"
    })
  end

  def call(conn, {:error, :invalid_invoice_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_invoice_amount", error: "Invoice amount must be greater than zero"})
  end

  def call(conn, {:error, :invalid_invoice_line_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_invoice_line_amount", error: "Invoice line amounts are invalid"})
  end

  def call(conn, {:error, :invoice_line_discount_exceeds_subtotal}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invoice_line_discount_exceeds_subtotal",
      error: "Invoice line discount cannot exceed the line subtotal"
    })
  end

  def call(conn, {:error, :invalid_renewal_period}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_renewal_period",
      error: "Custom renewals require a valid service period end date"
    })
  end

  def call(conn, {:error, :self_referral_not_allowed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "self_referral_not_allowed", error: "Self referrals are not allowed"})
  end

  def call(conn, {:error, :referral_membership_user_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "referral_membership_user_mismatch",
      error: "Referral membership must belong to the referred user"
    })
  end

  def call(conn, {:error, :referral_reward_already_exists}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "referral_reward_already_exists",
      error: "Referral reward already exists for this event"
    })
  end

  def call(conn, {:error, {:membership_mismatch, _field}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "membership_mismatch",
      error: "Finance record belongs to a different membership"
    })
  end

  def call(conn, {:error, :invalid_date}) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: "invalid_date", error: "Bad request"})
  end

  def call(conn, {:error, :invalid_cursor}) do
    conn
    |> put_status(:bad_request)
    |> json(%{code: "invalid_cursor", error: "Invalid pagination cursor"})
  end

  def call(conn, {:error, :invalid_email}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_email", error: "A recipient email and setup token are required"})
  end

  def call(conn, {:error, :mail_delivery_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "mail_delivery_unavailable",
      error: "Email delivery is not currently available"
    })
  end

  def call(conn, {:error, :owner_email_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "owner_email_required",
      error: "An initial admin email is required to provision an organization"
    })
  end

  def call(conn, {:error, :invalid_athletes}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_athletes",
      error: "Assigned workouts may target active athletes or members of this organization only"
    })
  end

  # ADR-125: personal member programming needs an explicit package grant.
  def call(conn, {:error, :member_programming_not_entitled, details}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "member_programming_not_entitled",
      error:
        "The member's package does not include personal programming " <>
          "(personal_programming channel and execute_assigned_workouts capability)",
      params: details
    })
  end

  def call(conn, {:error, :class_variant_requires_single_member}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "class_variant_requires_single_member",
      error: "A member's class version must target exactly one member"
    })
  end

  def call(conn, {:error, :slot_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "slot_not_found", error: "Class not found"})
  end

  def call(conn, {:error, :invalid_programming_mode}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_programming_mode", error: "Unknown programming mode"})
  end

  def call(conn, {:error, :workout_reassignment_not_supported}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "workout_reassignment_not_supported",
      error:
        "Assigned workout edits keep the workout template fixed; assign a different workout from the workout library"
    })
  end

  def call(conn, {:error, :workout_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "workout_not_found", error: "Workout not found"})
  end

  def call(conn, {:error, {:substitution_failed, _}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "substitution_failed", error: "Workout substitution failed"})
  end

  def call(conn, {:error, :workout_not_published}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "workout_not_published", error: "Target workout is not published"})
  end

  def call(conn, {:error, :already_published}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "already_published", error: "Workout is already published"})
  end

  # ADR-180: which text sections stop a sectioned workout from publishing.
  def call(conn, {:error, {:invalid_text_sections, problems}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_text_sections",
      error: "Every section needs its text and a timer",
      details: %{sections: problems}
    })
  end

  def call(conn, {:error, :no_sections}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "no_sections",
      error: "Workout must have at least one section before publishing"
    })
  end

  def call(conn, {:error, :invalid_scale_level}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_scale_level", error: "Invalid scale level"})
  end

  def call(conn, {:error, :already_completed}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "already_completed", error: "Execution already completed"})
  end

  # ADR-148 media uploads and ADR-142 public profiles.
  def call(conn, {:error, reason})
      when reason in [
             :invalid_media_purpose,
             :invalid_media_type,
             :invalid_media_size,
             :media_too_large,
             :media_type_mismatch,
             :media_has_metadata,
             :media_unreadable,
             :media_upload_missing,
             :invalid_media,
             :too_many_photos,
             :public_profile_empty,
             :unknown_filter_surface,
             :invalid_filter,
             :filter_too_large,
             :invalid_filter_name,
             :too_many_saved_filters
           ] do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: to_string(reason), error: "The upload or profile was rejected."})
  end

  def call(conn, {:error, :media_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{code: "media_not_found", error: "Media not found."})
  end

  def call(conn, {:error, :media_key_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "media_key_forbidden", error: "Forbidden."})
  end

  def call(conn, {:error, :media_storage_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{code: "media_storage_unavailable", error: "Storage is unavailable; try again."})
  end

  def call(conn, {:error, :stale_profile}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "stale_profile", error: "The profile changed meanwhile; reload it."})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{code: "forbidden", error: "Forbidden"})
  end

  def call(conn, {:error, :organization_context_required}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "organization_context_required",
      error: "An organization context is required"
    })
  end

  def call(conn, {:error, :organization_context_mismatch}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "organization_context_mismatch",
      error: "The selected organization does not match this resource"
    })
  end

  def call(conn, {:error, :slot_full}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "slot_full", error: "Slot is full"})
  end

  def call(conn, {:error, :slot_in_past}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "slot_in_past", error: "Slot is in the past"})
  end

  def call(conn, {:error, :already_booked}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "already_booked", error: "User already booked this slot"})
  end

  def call(conn, {:error, :slot_not_booked_by_member}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "slot_not_booked_by_member",
      error: "Choose a class booked by this member on the selected day"
    })
  end

  def call(conn, {:error, :folder_parent_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "folder_not_found", error: "The chosen library folder does not exist"})
  end

  def call(conn, {:error, :invalid_workout_icon}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_workout_icon", error: "Choose a single emoji as the icon"})
  end

  def call(conn, {:error, :folder_cycle}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "folder_cycle", error: "A folder cannot be moved inside itself"})
  end

  def call(conn, {:error, :class_placement_requires_member}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "class_placement_requires_member",
      error: "Only active members of this organization can be placed in a class"
    })
  end

  def call(conn, {:error, :idempotency_key_conflict}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "idempotency_key_conflict",
      error: "This operation id was already used for a different request"
    })
  end

  def call(conn, {:error, :booking_not_pending}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "booking_not_pending", error: "Booking is no longer pending"})
  end

  def call(conn, {:error, :active_challenge_limit_reached}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "active_challenge_limit_reached",
      error: "A maximum of 3 overlapping active challenges is allowed"
    })
  end

  def call(conn, {:error, :leaderboard_refresh_failed}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "leaderboard_refresh_failed",
      error: "Leaderboard update is temporarily unavailable"
    })
  end

  # ADR-117 reviewed tenant purge workflow.
  def call(conn, {:error, :organization_purge_exists}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "organization_purge_exists",
      error: "This organization already has an open purge request"
    })
  end

  def call(conn, {:error, :organization_purge_in_progress}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "organization_purge_in_progress",
      error: "Cancel the open purge request before changing this organization's status"
    })
  end

  def call(conn, {:error, :invalid_purge_transition}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "invalid_purge_transition",
      error: "The purge request is not in a state that allows this action"
    })
  end

  def call(conn, {:error, :purge_confirmation_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "purge_confirmation_mismatch",
      error: "Type the organization slug exactly to approve the purge"
    })
  end

  # ADR-122 organization slug rename.
  def call(conn, {:error, :invalid_slug}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_slug",
      error: "Use 3-63 lowercase letters, digits and single hyphens"
    })
  end

  def call(conn, {:error, :slug_unchanged}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "slug_unchanged", error: "The new slug matches the current slug"})
  end

  def call(conn, {:error, :slug_confirmation_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "slug_confirmation_mismatch",
      error: "Type the current organization slug exactly to confirm the rename"
    })
  end

  def call(conn, {:error, :slug_taken}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "slug_taken",
      error: "This slug belongs to another organization or is reserved as its previous slug"
    })
  end

  def call(conn, {:error, :slug_rename_blocked_by_purge}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "slug_rename_blocked_by_purge",
      error: "Cancel the open purge request before renaming this organization's slug"
    })
  end

  def call(conn, {:error, :purge_job_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "purge_job_unavailable",
      error: "Background processing is unavailable; resume the purge later"
    })
  end

  def call(conn, {:error, :cannot_share_prs_with_self}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "cannot_share_prs_with_self", error: "You already own these records"})
  end

  def call(conn, {:error, :pr_organization_unavailable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "pr_organization_unavailable",
      error: "PRs can only be recorded in a gym you are an active member of"
    })
  end

  # ADR-140 §3 injury updates.
  def call(conn, {:error, :empty_update}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "empty_update", error: "Write something or change at least one field"})
  end

  def call(conn, {:error, :note_too_long}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "note_too_long", error: "The update text is too long"})
  end

  # ADR-139 ladder moves and reply requests.
  @journal_errors %{
    unknown_kind: {:unprocessable_entity, "Unknown journal entry kind"},
    visibility_not_allowed: {:unprocessable_entity, "This entry cannot take that visibility"},
    no_gym_for_entry: {:unprocessable_entity, "A personal entry has no coach to show it to"},
    no_active_coach: {:unprocessable_entity, "You have no active coach in this entry's gym"},
    question_required: {:unprocessable_entity, "Ask your coach a question"},
    question_too_long: {:unprocessable_entity, "The question is too long"},
    note_organization_unavailable: {:unprocessable_entity, "That gym is not available"},
    stale: {:conflict, "This entry changed meanwhile; reload it"},
    # ADR-162: one journal across providers.
    unknown_provider: {:unprocessable_entity, "That is not one of your active providers"},
    unknown_coach: {:unprocessable_entity, "That is not a coach of one of your active providers"},
    empty_audience:
      {:unprocessable_entity, "Choose at least one coach, or keep the entry private"},
    audience_not_supported: {:unprocessable_entity, "This entry cannot be shared that way"},
    export_in_progress: {:conflict, "An export is already being prepared"},
    invalid_history_kind: {:unprocessable_entity, "Use workouts or classes"}
  }

  def call(conn, {:error, reason}) when is_map_key(@journal_errors, reason) do
    {status, message} = Map.fetch!(@journal_errors, reason)

    conn
    |> put_status(status)
    |> json(%{code: Atom.to_string(reason), error: message})
  end

  def call(conn, {:error, :comment_conflict}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "comment_conflict", error: "This comment id belongs to another entry"})
  end

  def call(conn, {:error, :injury_already_active}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "injury_already_active", error: "This injury is already active"})
  end

  # ADR-140 §2 Πώς νιώθω.
  def call(conn, {:error, :check_in_organization_unavailable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "check_in_organization_unavailable",
      error: "Check-ins can only be recorded in a gym you are an active member of"
    })
  end

  # ADR-160 Buddy για στήριξη.
  @buddy_errors %{
    buddy_limit_reached: {:conflict, "You can have up to two buddies or invitations"},
    buddy_already_invited: {:conflict, "You already invited this person"},
    buddy_invite_expired: {:conflict, "This invitation has expired"},
    buddy_link_closed: {:conflict, "This buddy link has already ended"},
    buddy_invite_unavailable: {:conflict, "This invitation link no longer works"},
    cannot_buddy_self: {:unprocessable_entity, "You cannot be your own buddy"},
    not_eligible_for_buddy:
      {:forbidden,
       "Invite your coach, someone from your clubs or someone you follow, or send a link"},
    invalid_buddy_link: {:unprocessable_entity, "Check the invitation"},
    invalid_receives_weekly_summary:
      {:unprocessable_entity, "receives_weekly_summary must be true or false"},
    message_too_long: {:unprocessable_entity, "The message is at most 280 characters"},
    invalid_support_source: {:unprocessable_entity, "Use craving or quick"},
    support_rate_limited:
      {:too_many_requests, "You asked for support a few times this hour; your buddies have it"},
    no_active_buddies: {:conflict, "Add a buddy first"},
    already_undone: {:conflict, "This request was already taken back"},
    undo_window_passed: {:conflict, "Your buddies have already been told"},
    invalid_reply_kind: {:unprocessable_entity, "Use here, walk, call or text"},
    reply_text_required: {:unprocessable_entity, "Write a few words"},
    reply_too_long: {:unprocessable_entity, "A reply is at most 500 characters"},
    invalid_reply_text: {:unprocessable_entity, "Check the reply"},
    invalid_reply: {:unprocessable_entity, "Check the reply"},
    invalid_quiet_hours: {:unprocessable_entity, "Quiet hours are two different times, HH:MM"},
    invalid_phone: {:unprocessable_entity, "Check the phone number"},
    invalid_share_phone: {:unprocessable_entity, "share_phone must be true or false"},
    phone_required: {:unprocessable_entity, "Add a phone number to share it"},
    summary_required: {:unprocessable_entity, "Turn on the weekly summary first"},
    invalid_summary_sharing: {:unprocessable_entity, "Use true or false"},
    message_body_required: {:unprocessable_entity, "Write a message"},
    message_too_long_body: {:unprocessable_entity, "A message is at most 2000 characters"},
    buddy_link_read_only: {:conflict, "This buddy link has ended; the conversation is read-only"}
  }

  def call(conn, {:error, reason}) when is_map_key(@buddy_errors, reason) do
    {status, message} = Map.fetch!(@buddy_errors, reason)

    conn
    |> put_status(status)
    |> json(%{code: Atom.to_string(reason), error: message})
  end

  # ADR-169 Partners.
  @partner_errors %{
    partners_disabled: {:forbidden, "This gym has switched Partners off"},
    partners_not_offered:
      {:forbidden, "Partners is only in clubs whose members the gym verified"},
    not_club_member: {:forbidden, "Only members of this club take part"},
    partner_profile_required: {:conflict, "Turn on your Partners profile in this club first"},
    partner_profile_suspended:
      {:forbidden, "Staff have hidden your Partners profile in this club"},
    invalid_partner_level: {:unprocessable_entity, "Choose your level"},
    invalid_partner_times: {:unprocessable_entity, "Choose when you train"},
    invalid_partner_goals: {:unprocessable_entity, "Choose one to three goals"},
    invalid_partner_gender: {:unprocessable_entity, "Unknown gender"},
    invalid_partner_gender_preference: {:unprocessable_entity, "Unknown preference"},
    invalid_partner_active: {:unprocessable_entity, "active must be true or false"},
    partner_about_too_long: {:unprocessable_entity, "At most 140 characters"},
    invalid_direction: {:unprocessable_entity, "Like or pass"},
    invalid_swipe: {:unprocessable_entity, "That swipe isn't possible"},
    invalid_match: {:conflict, "That match isn't possible"},
    partner_swipe_limit: {:too_many_requests, "That's enough swiping for today"},
    partner_already_matched: {:conflict, "You are already partners"},
    partner_match_ended: {:conflict, "This match has ended"},
    invalid_end_reason: {:unprocessable_entity, "Unknown reason"},
    partner_match_read_only: {:conflict, "This conversation is read-only"},
    partner_plans_unavailable: {:unprocessable_entity, "Class plans are for a gym's own clubs"},
    invalid_partner_message: {:unprocessable_entity, "Check the message"},
    invalid_partners_visible: {:unprocessable_entity, "visible must be true or false"},
    invalid_partners_enabled: {:unprocessable_entity, "partners_enabled must be true or false"},
    cannot_block_self: {:unprocessable_entity, "You can't block yourself"},
    invalid_user: {:unprocessable_entity, "Unknown person"}
  }

  def call(conn, {:error, reason}) when is_map_key(@partner_errors, reason) do
    {status, message} = Map.fetch!(@partner_errors, reason)

    conn
    |> put_status(status)
    |> json(%{code: Atom.to_string(reason), error: message})
  end

  # ADR-159 Ευεξία and Λιγούρα.
  def call(conn, {:error, {:invalid_wellness_value, errors}}) when is_map(errors) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_wellness_value", error: "The entry is not valid", errors: errors})
  end

  @wellness_errors %{
    unknown_wellness_kind: "Use water, sleep or meal",
    wellness_organization_unavailable: "Entries can only name a gym you are an active member of",
    unknown_time_zone: "The time zone is not known",
    invalid_occurred_at: "occurred_at must be an ISO-8601 date-time",
    occurred_in_future: "An entry cannot be in the future",
    occurred_too_long_ago: "Entries can be added or moved at most 7 days back",
    invalid_craving_trigger: "Use stress, fatigue, boredom, social, hunger or other",
    invalid_date: "Dates must be ISO-8601 (YYYY-MM-DD), from before to",
    date_window_too_long: "Ask for at most 92 days at a time",
    unknown_wellness_section: "Use the sections wellness and cravings"
  }

  def call(conn, {:error, :health_data_consent_required}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      code: "health_data_consent_required",
      error: "Agree to keep health data first; it stays private unless you share it"
    })
  end

  def call(conn, {:error, reason}) when is_map_key(@wellness_errors, reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: Atom.to_string(reason), error: Map.fetch!(@wellness_errors, reason)})
  end

  def call(conn, {:error, :invalid_range}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "invalid_range", error: "from must be before to, at most a year apart"})
  end

  # ADR-126 refund receipts, reconciliation and accounting exports.
  def call(conn, {:error, :reconciliation_reference_conflict}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "reconciliation_reference_conflict",
      error: "This provider reference was already recorded with a different amount, date or type"
    })
  end

  def call(conn, {:error, :reconciliation_target_already_matched}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      code: "reconciliation_target_already_matched",
      error: "This payment or reversal is already matched to another statement line"
    })
  end

  def call(conn, {:error, :invalid_reconciliation_target}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_reconciliation_target",
      error: "Choose a payment or reversal to match"
    })
  end

  def call(conn, {:error, :invalid_export_range}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "invalid_export_range",
      error: "Choose a start date that is not in the future and an end date on or after it"
    })
  end

  def call(conn, {:error, :export_range_too_long}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{code: "export_range_too_long", error: "Export at most five years at a time"})
  end

  def call(conn, {:error, :export_job_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{
      code: "export_job_unavailable",
      error: "Background processing is unavailable; try a shorter range or retry later"
    })
  end

  def call(conn, {:error, :accounting_export_not_ready}) do
    conn
    |> put_status(:conflict)
    |> json(%{code: "accounting_export_not_ready", error: "This export has not completed"})
  end

  def call(conn, {:error, :accounting_export_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{
      code: "accounting_export_failed",
      error: "The accounting export could not be built"
    })
  end

  # ADR-097 Phase B: booking rules, perks, freezes and facility.
  @phase_b_errors %{
    finance_membership_frozen: {:forbidden, "The membership is frozen"},
    finance_time_window_not_included: {:forbidden, "This time is outside the package's hours"},
    finance_location_not_included: {:forbidden, "This location is not included in the package"},
    invalid_freeze_dates: {:unprocessable_entity, "The freeze dates are invalid"},
    freeze_in_past: {:unprocessable_entity, "A freeze cannot start in the past"},
    freeze_not_included: {:unprocessable_entity, "The package does not include freezes"},
    freeze_overlaps: {:conflict, "The freeze overlaps another freeze"},
    freeze_allowance_exceeded:
      {:unprocessable_entity, "The freeze exceeds the yearly freeze days"},
    freeze_already_cancelled: {:conflict, "The freeze is already cancelled"},
    slot_not_full: {:conflict, "The class still has free spots"},
    # ADR-176: a draft class has no WOD yet.
    class_not_published: {:conflict, "This class isn't open yet"},
    invalid_time_zone: {:unprocessable_entity, "Choose a known time zone"},
    time_zone_required: {:unprocessable_entity, "The gym's time zone must be set"},
    invalid_guest_name: {:unprocessable_entity, "Enter the guest's name"},
    guest_already_booked: {:conflict, "A guest is already booked for this class"},
    booking_not_waitlisted: {:conflict, "The booking is not on the waitlist"},
    location_not_found: {:not_found, "Location not found"},
    location_archived: {:unprocessable_entity, "The location is archived"},
    # ADR-186: branch-scoped staff.
    location_out_of_scope: {:forbidden, "This is at a branch you don't work at"},
    location_required: {:unprocessable_entity, "Choose the branch"},
    location_scope_exceeded: {:forbidden, "You can only give access to your own branches"},
    invalid_location_scope: {:unprocessable_entity, "Choose every branch or at least one branch"},
    owner_location_scope: {:unprocessable_entity, "Owners work at every branch"},
    cannot_change_own_membership: {:forbidden, "Someone else changes your own access"},
    promotion_location_not_included:
      {:unprocessable_entity, "This promotion is not valid at the branches of this package"},
    # ADR-191: partner perks.
    perk_transition_invalid: {:conflict, "The perk can't take this step now"},
    perk_ended: {:unprocessable_entity, "The perk's last day has passed"},
    perk_read_only: {:conflict, "An ended perk can't be changed"},
    perk_locked_after_claims:
      {:conflict, "Members already claimed this perk: its benefit and code stay as they saw them"},
    perk_cap_below_claims:
      {:unprocessable_entity, "The limit can't be lower than the claims already made"},
    perk_has_claims: {:conflict, "Members claimed this perk; end it instead"},
    perk_codes_required: {:unprocessable_entity, "Add the partner's codes before publishing"},
    perk_codes_not_used: {:unprocessable_entity, "Only a perk with a unique code per member has codes"},
    invalid_perk_codes: {:unprocessable_entity, "Each code needs 1 to 64 letters or digits"},
    invalid_perk_packages: {:unprocessable_entity, "Choose packages of this business"},
    perk_not_available: {:conflict, "This perk isn't available now"},
    perk_sold_out: {:conflict, "This perk has run out"},
    perk_member_limit: {:conflict, "You've already used this perk as often as it allows"},
    perk_codes_exhausted: {:conflict, "This perk has run out of codes"},
    perk_claim_already_used: {:conflict, "This perk was already used"},
    perk_claim_not_open: {:conflict, "This claim is no longer open"},
    perk_not_qr: {:unprocessable_entity, "This perk isn't redeemed with a QR"},
    perk_outside_hours: {:conflict, "This perk works only at its set days and hours"},
    perk_period_sold_out: {:conflict, "This perk has run out for now; it opens again next period"},
    perk_member_period_limit:
      {:conflict, "You've used this perk as often as it allows this period"},
    invalid_perk_groups: {:unprocessable_entity, "Choose groups of this business"},
    invalid_redemption_method: {:unprocessable_entity, "Choose how members redeem the perk"},
    invalid_verification_link: {:not_found, "This link isn't valid"},
    verification_link_expired: {:gone, "This link expired; ask for the QR again"},
    # ADR-098
    form_review_closed: {:conflict, "The form review is already closed"},
    appointment_slot_cancelled: {:conflict, "The appointment was cancelled"},
    appointment_slot_in_past: {:unprocessable_entity, "The appointment has already started"},
    appointment_slot_full: {:conflict, "The appointment is full"},
    appointment_format_not_included:
      {:forbidden, "This session format is not included in the package"},
    appointment_coach_not_included: {:forbidden, "This coach is not included in the package"},
    appointment_not_active: {:conflict, "The appointment is no longer active"},
    appointment_coach_not_staff: {:unprocessable_entity, "Choose a coach of this gym"},
    invalid_attendance_status: {:unprocessable_entity, "Attendance must be attended or no_show"},
    # TD-105: member self check-in to a booked class.
    check_in_not_open: {:conflict, "Check-in opens 30 minutes before the class"},
    check_in_closed: {:conflict, "The class has ended"},
    attendance_already_recorded: {:conflict, "Your attendance was already recorded"},
    attendance_requires_approved_booking: {:conflict, "Only an approved booking can check in"},
    add_on_base_required:
      {:unprocessable_entity, "The member needs a compatible membership first"},
    corporate_package_requires_enrollment:
      {:unprocessable_entity, "Corporate seats are added through the corporate client"},
    beneficiary_is_payer: {:unprocessable_entity, "The payer is already on the membership"},
    not_a_shared_membership: {:unprocessable_entity, "This membership is not shared"},
    beneficiary_limit_reached: {:conflict, "The membership has no room for more people"},
    minor_beneficiaries_not_allowed:
      {:unprocessable_entity, "This package does not allow minors"},
    not_a_corporate_package: {:unprocessable_entity, "Choose a corporate package"},
    already_enrolled: {:conflict, "The member already has a seat"},
    corporate_seats_full: {:conflict, "All seats are taken"},
    corporate_invoice_closed: {:conflict, "The invoice is already paid or void"},
    invalid_invoice_status: {:unprocessable_entity, "Status must be paid or void"},
    corporate_enrollment_not_found: {:not_found, "No corporate plan matches"},
    corporate_seat_billed_to_company: {:unprocessable_entity, "The company pays for this seat"},
    add_on_base_ended: {:unprocessable_entity, "The add-on's base membership has ended"},
    last_owner: {:conflict, "A gym needs at least one owner"},
    owner_required: {:forbidden, "Only gym owners can create gyms"},
    # ADR-170: platform plans and the solo-coach tier.
    vendor_required: {:forbidden, "Only the platform team can do this"},
    coach_practice_exists: {:conflict, "You already run a practice as an independent coach"},
    plan_limit_reached:
      {:conflict, "Your plan has no free staff seat; ask us about a bigger plan"},
    unknown_plan: {:unprocessable_entity, "Choose one of the platform plans"},
    invalid_plan_audience: {:unprocessable_entity, "Audience must be gym or coach"},
    invalid_subscription_status:
      {:unprocessable_entity, "Choose trialing, active, past_due, cancelled or comped"},
    trial_end_required: {:unprocessable_entity, "A trial needs an end date in the future"},
    invalid_price: {:unprocessable_entity, "A price is a whole number of cents, zero or more"},
    invalid_name: {:unprocessable_entity, "A name has 2 to 120 characters"},
    machine_retired: {:unprocessable_entity, "This machine is retired"},
    # ADR-144: trials.
    trials_disabled: {:unprocessable_entity, "This box doesn't offer trials right now"},
    class_not_open_to_trials: {:unprocessable_entity, "This class doesn't take trials"},
    beyond_trial_horizon: {:unprocessable_entity, "Trials can't be booked this far ahead"},
    no_trial_seats: {:conflict, "No trial seats left in this class"},
    weekly_trial_limit_reached: {:conflict, "This week's trials are full"},
    already_member: {:unprocessable_entity, "You're already a member of this box"},
    trial_for_first_timers_only:
      {:unprocessable_entity, "Trials here are for people who were never members"},
    trial_already_used: {:conflict, "You've already had your trial here"},
    trial_already_open: {:conflict, "You already have a trial booked here"},
    invalid_trial_transition: {:conflict, "The trial can't take this step now"},
    class_not_found: {:not_found, "The class no longer exists"},
    # ADR-167: seasons.
    season_not_open: {:conflict, "This season isn't taking requests"},
    season_full: {:conflict, "Every place in this season is taken"},
    season_already_requested: {:conflict, "You already asked for a place in this season"},
    season_place_confirmed: {:conflict, "Your place is confirmed; talk to the box to cancel it"},
    invalid_season_transition: {:conflict, "This request can't take this step now"},
    invalid_season_status: {:unprocessable_entity, "Choose draft, published or cancelled"},
    season_closed: {:conflict, "This season has ended or was cancelled"},
    season_schedule_locked:
      {:conflict, "The dates and programme are fixed once a participant is confirmed"},
    capacity_below_participants:
      {:unprocessable_entity, "Capacity can't go below the confirmed participants"},
    season_has_enrollments:
      {:conflict, "Members already asked for this season; cancel it instead"},
    programme_workout_unavailable:
      {:unprocessable_entity, "Every programme workout must be a published workout of this box"},
    # ADR-143: member groups, open clubs and reports.
    member_groups_disabled: {:forbidden, "This box doesn't let members start groups"},
    group_not_open: {:unprocessable_entity, "This group isn't open to join"},
    hand_over_first: {:unprocessable_entity, "Make someone else an admin before you leave"},
    invalid_decision: {:unprocessable_entity, "Approve or decline"},
    invalid_member_groups: {:unprocessable_entity, "Unknown group rule"},
    invalid_join_policy: {:unprocessable_entity, "Unknown way to join"},
    cannot_report_own: {:unprocessable_entity, "You can't report your own post"},
    invalid_reason: {:unprocessable_entity, "Choose a reason"},
    invalid_target: {:unprocessable_entity, "That can't be reported"},
    invalid_action: {:unprocessable_entity, "That action doesn't apply here"},
    package_not_found: {:unprocessable_entity, "Choose an active package of this box"},
    # ADR-168: PT squads.
    too_many_squads: {:unprocessable_entity, "You already run the most squads you can"},
    squad_full: {:unprocessable_entity, "This squad is full"},
    squad_archived: {:conflict, "This squad is archived"},
    coach_archives_instead: {:unprocessable_entity, "Archive the squad instead of leaving it"},
    # ADR-153: club events.
    event_cancelled: {:conflict, "This event was cancelled"},
    event_started: {:conflict, "This event has already started"},
    event_not_over: {:conflict, "The event hasn't ended yet"},
    not_invited: {:forbidden, "This event is for the club's members"},
    guests_not_allowed: {:forbidden, "This event doesn't take guests"},
    inviter_not_going: {:conflict, "The friend who invited you isn't going any more"},
    guest_limit_reached: {:conflict, "This invitation has no places left"},
    invalid_invite: {:not_found, "This invitation link isn't valid"},
    invalid_scope: {:unprocessable_entity, "Choose this event or this and following"},
    invalid_repeat: {:unprocessable_entity, "Repeat until a date on or after the first event"},
    event_is_free: {:unprocessable_entity, "This event is free"},
    already_paid: {:conflict, "Already marked as paid"},
    not_going: {:conflict, "This person doesn't hold a place"},
    trial_offer_already_sent: {:conflict, "The trial offer was already sent"},
    event_not_found: {:not_found, "No such event at this box"},
    nobody_to_offer: {:unprocessable_entity, "Nobody who came is waiting for a trial offer"},
    # ADR-185: hosts, co-hosts and refunds.
    invalid_host: {:unprocessable_entity, "Choose yourself or a business where you run events"},
    event_rate_limited:
      {:too_many_requests, "You've made a lot of events lately; try again tomorrow"},
    box_not_found: {:not_found, "No published box page at that address"},
    cannot_cohost_own_event: {:unprocessable_entity, "A box can't co-host its own event"},
    group_event: {:unprocessable_entity, "A member group's own event can't have co-hosts"},
    already_invited: {:conflict, "That box was already asked"},
    cohost_limit_reached: {:unprocessable_entity, "This event has as many co-hosts as it can"},
    # ADR-185: co-hosts asked as the event is created.
    invalid_cohosts: {:unprocessable_entity, "cohost_slugs must be a list of page addresses"},
    duplicate_cohost: {:unprocessable_entity, "The same box is asked twice"},
    not_pending: {:conflict, "This request was already answered"},
    not_paid: {:conflict, "This place isn't paid"},
    already_refunded: {:conflict, "Already refunded"},
    invalid_refund: {:unprocessable_entity, "Refund up to what was paid"},
    invalid_machine_event: {:unprocessable_entity, "Unknown machine log entry"},
    not_enough_stock: {:unprocessable_entity, "There is not that much in stock"},
    invalid_movement: {:unprocessable_entity, "Unknown stock change"},
    confirmation_mismatch: {:unprocessable_entity, "Type the gym's slug to confirm"},
    cleaning_area_archived: {:unprocessable_entity, "That area is archived"},
    cleaning_already_finished: {:conflict, "This cleaning is already finished"},
    cleaning_finished_before_start: {:unprocessable_entity, "Finish cannot be before start"},
    not_a_coach: {:unprocessable_entity, "That person is not a coach here"},
    not_a_client: {:unprocessable_entity, "That person is not a member or athlete here"},
    only_athletes_self_assigned: {:unprocessable_entity, "Coaches can take athletes only"},
    not_your_client: {:forbidden, "Not one of your clients"},
    roles_required: {:unprocessable_entity, "Choose at least one role"},
    invalid_role: {:unprocessable_entity, "Unknown role"},
    invalid_payment_amount: {:unprocessable_entity, "Enter an amount above zero"},
    payment_exceeds_balance: {:unprocessable_entity, "The payment is more than the balance due"},
    corporate_invoice_has_payments: {:conflict, "Reverse the payments before voiding"},
    corporate_billing_email_missing: {:unprocessable_entity, "The client has no billing email"},
    # ADR-155: QR check-in and Wallet.
    invalid_door_code: {:unprocessable_entity, "This door code has expired; scan it again"},
    invalid_scan_token: {:unprocessable_entity, "Scan the door again"},
    booking_not_in_window: {:unprocessable_entity, "That booking isn't open for check-in now"},
    undo_expired: {:conflict, "It's too late to undo this check-in"},
    invalid_undo_token: {:unprocessable_entity, "Nothing to undo"},
    invalid_member_code: {:unprocessable_entity, "This code isn't valid here or has expired"},
    not_a_member: {:unprocessable_entity, "This person isn't a member of the box"},
    invalid_pass: {:unprocessable_entity, "This Wallet card isn't valid here"},
    pass_revoked: {:unprocessable_entity, "This Wallet card was revoked"},
    override_not_allowed: {:forbidden, "The box doesn't allow checking in despite a problem"},
    check_in_problems: {:conflict, "There is a problem with this member's package"},
    choose_booking: {:conflict, "Choose which booking to check in to"},
    invalid_check_in_method: {:unprocessable_entity, "Unknown check-in method"},
    invalid_wallet_platform: {:unprocessable_entity, "Choose Apple or Google Wallet"},
    wallet_not_configured: {:service_unavailable, "Wallet cards aren't available on this server"},
    invalid_download_link: {:unprocessable_entity, "This download link has expired"},
    wallet_pass_conflict: {:conflict, "The card is being created; try again"},
    wallet_requires_static_code:
      {:conflict, "This box uses rotating codes, so its check-in card can't go in a Wallet"},
    member_code_not_static:
      {:conflict, "This box uses rotating codes; there is nothing to reset"},
    member_code_revoked: {:unprocessable_entity, "This code was revoked"},
    invalid_poster_setting: {:unprocessable_entity, "Say whether the poster is on"},
    # ADR-173: NFC door tags and widgets.
    invalid_nfc_setting: {:unprocessable_entity, "Say whether the NFC tag is on"},
    invalid_widget_token: {:unauthorized, "Open the app to refresh the widget"},
    # ADR-157: photos and videos in posts.
    too_many_media: {:unprocessable_entity, "A post carries up to ten photos or one video"},
    mixed_media: {:unprocessable_entity, "A post carries photos or a video, not both"},
    media_quota_exceeded:
      {:unprocessable_entity, "You have too many uploads waiting; post or remove some first"},
    video_unavailable: {:service_unavailable, "Videos aren't available on this server"},
    media_in_post: {:conflict, "This upload is in a post; delete the post instead"},
    media_not_ready: {:conflict, "The photo is still processing"},
    invalid_alt_text: {:unprocessable_entity, "Alternative text is at most 500 characters"},
    alt_text_unavailable: {:service_unavailable, "Suggestions aren't available right now"},
    # ADR-158: Σώμα.
    invalid_metric: {:unprocessable_entity, "Check this measurement"},
    snapshot_empty: {:unprocessable_entity, "Add at least one measurement or photo"},
    invalid_body_visibility: {:unprocessable_entity, "Choose who sees this snapshot"},
    body_notes_too_long: {:unprocessable_entity, "Notes are at most 2000 characters"},
    invalid_pose: {:unprocessable_entity, "Choose front, side, back or other"},
    too_many_body_photos: {:unprocessable_entity, "A snapshot holds up to four photos"},
    pose_taken: {:conflict, "This snapshot already has a photo of that pose"},
    body_photo_consent_required:
      {:forbidden, "Agree to keep body photos first; they stay private unless you share them"},
    invalid_consent_scope: {:unprocessable_entity, "Unknown consent"},
    invalid_units: {:unprocessable_entity, "Choose metric or imperial units"},
    invalid_taken_at: {:unprocessable_entity, "Check the date of the measurement"},
    unknown_metric: {:unprocessable_entity, "Unknown measurement"},
    invalid_range: {:unprocessable_entity, "Choose 1m, 3m, 1y or all"},
    invalid_body_settings: {:unprocessable_entity, "Check your body settings"},
    share_confirmation_required:
      {:unprocessable_entity, "Confirm that you want to post these photos"},
    share_needs_two_snapshots: {:unprocessable_entity, "Choose two different snapshots"},
    share_photo_missing:
      {:unprocessable_entity, "Both snapshots need a ready photo of that pose"},
    # ADR-161: Garmin and connected devices.
    garmin_not_configured: {:service_unavailable, "Garmin isn't available on this server yet"},
    garmin_unavailable:
      {:service_unavailable, "Garmin isn't answering right now; try again later"},
    device_already_connected: {:conflict, "Garmin is already connected"},
    device_not_connected: {:unprocessable_entity, "Garmin isn't connected"},
    device_reconnect_required: {:conflict, "Reconnect Garmin to sync again"},
    sync_too_soon:
      {:too_many_requests, "Garmin was synced a moment ago; try again in a few minutes"},
    invalid_sync_prefs:
      {:unprocessable_entity,
       "Choose on or off for workouts, sleep, weight and resting heart rate"},
    invalid_backfill_days: {:unprocessable_entity, "Choose 0, 30 or 90 days of history"},
    import_already_settled: {:conflict, "This workout was already sorted out"},
    unknown_device_candidate:
      {:unprocessable_entity, "Choose one of the suggested classes or workouts"},
    device_confirmation_required:
      {:unprocessable_entity, "Choose a class or workout, or keep it as its own entry"},
    invalid_daily_stat_metric: {:unprocessable_entity, "Choose resting_hr or steps"},
    # ADR-172: Apple Health and Health Connect from the store apps.
    phone_health_not_connected:
      {:unprocessable_entity, "Connect it in the app first, under Connected devices"},
    phone_health_batch_too_large:
      {:unprocessable_entity, "Send at most 500 records per list in one batch"},
    invalid_phone_health_batch: {:unprocessable_entity, "Send the records as lists"},
    # ADR-171: push to the store apps.
    native_push_not_configured:
      {:service_unavailable, "Push to the app isn't available on this server yet"}
  }

  def call(conn, {:error, reason}) when is_map_key(@phase_b_errors, reason) do
    {status, message} = Map.fetch!(@phase_b_errors, reason)
    package_contract_error(conn, status, to_string(reason), message, %{})
  end

  def call(conn, {:error, reason, details}) when is_map_key(@phase_b_errors, reason) do
    {status, message} = Map.fetch!(@phase_b_errors, reason)
    package_contract_error(conn, status, to_string(reason), message, details)
  end

  def call(conn, {:error, :booking_window_closed, details}) do
    package_contract_error(
      conn,
      :unprocessable_entity,
      "booking_window_closed",
      "Booking for this class is not open yet",
      details
    )
  end

  def call(conn, {:error, {:package_commitment_active, details}}) do
    package_contract_error(
      conn,
      :conflict,
      "package_commitment_active",
      "The minimum commitment has not ended",
      details
    )
  end

  def call(conn, {:error, :package_commitment_active}) do
    package_contract_error(
      conn,
      :conflict,
      "package_commitment_active",
      "The minimum commitment has not ended",
      %{}
    )
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{code: "unexpected_server_error", error: "Unexpected server error"})
  end

  defp json_dsl_diagnostic(diagnostic) do
    %{
      code: to_string(diagnostic.code),
      severity: to_string(diagnostic.severity),
      line: diagnostic.line,
      column: diagnostic.column,
      params: Map.new(diagnostic.params, fn {key, value} -> {to_string(key), value} end)
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  # Credential failures use a bounded reason set; ops/observability alert rules
  # watch their rate for brute force and refresh-token reuse.
  defp emit_auth_anomaly(reason) do
    :telemetry.execute([:palee, :auth, :anomaly], %{count: 1}, %{reason: Atom.to_string(reason)})
  end

  defp emit_upload_rejection(reason) do
    :telemetry.execute(
      [:palee, :upload, :rejected],
      %{count: 1},
      %{context: "invoice", reason: reason}
    )
  end

  defp package_contract_error(conn, status, code, message, params) do
    conn
    |> put_status(status)
    |> json(%{code: code, error: message, params: params})
  end
end
