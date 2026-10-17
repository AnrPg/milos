defmodule MilosTrainingWeb.FallbackController do
  use MilosTrainingWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      code: "validation_failed",
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
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
             :public_profile_empty
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
    stale: {:conflict, "This entry changed meanwhile; reload it"}
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
    invalid_guest_name: {:unprocessable_entity, "Enter the guest's name"},
    guest_already_booked: {:conflict, "A guest is already booked for this class"},
    booking_not_waitlisted: {:conflict, "The booking is not on the waitlist"},
    location_not_found: {:not_found, "Location not found"},
    location_archived: {:unprocessable_entity, "The location is archived"},
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
    machine_retired: {:unprocessable_entity, "This machine is retired"},
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
    corporate_billing_email_missing: {:unprocessable_entity, "The client has no billing email"}
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
    :telemetry.execute([:milos, :auth, :anomaly], %{count: 1}, %{reason: Atom.to_string(reason)})
  end

  defp emit_upload_rejection(reason) do
    :telemetry.execute(
      [:milos, :upload, :rejected],
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
