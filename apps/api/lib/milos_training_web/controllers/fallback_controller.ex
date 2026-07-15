defmodule MilosTrainingWeb.FallbackController do
  use MilosTrainingWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)})
  end

  def call(conn, {:error, errors}) when is_list(errors) do
    normalized_errors =
      errors
      |> Enum.group_by(fn {field, _message} -> to_string(field) end, fn {_field, message} ->
        message
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: normalized_errors})
  end

  def call(conn, {:error, :invalid_current_password}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Current password is incorrect"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid credentials"})
  end

  def call(conn, {:error, :invalid_refresh_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid refresh token"})
  end

  def call(conn, {:error, :invalid_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "Invalid token"})
  end

  def call(conn, {:error, :token_issuance_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Authentication service unavailable"})
  end

  def call(conn, {:error, :registration_cleanup_failed}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Registration could not be completed"})
  end

  def call(conn, {:error, :auth_dependency_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Authentication dependency unavailable"})
  end

  def call(conn, {:error, :rate_limiter_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Rate limiter unavailable"})
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Not found"})
  end

  def call(conn, {:error, {:class_type_replacement_required, future_class_count}}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      error: "Future classes require a replacement class type",
      future_class_count: future_class_count
    })
  end

  def call(conn, {:error, :invalid_class_type_replacement}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Replacement class type must be a different active type"})
  end

  def call(conn, {:error, :last_active_class_type}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "At least one active class type must remain"})
  end

  def call(conn, {:error, :class_type_archived}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Archived class types cannot be modified or selected"})
  end

  def call(conn, {:error, :class_type_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Class type is missing or archived"})
  end

  def call(conn, {:error, :bad_request}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Bad request"})
  end

  def call(conn, {:error, :invalid_execution_source}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid execution source"})
  end

  def call(conn, {:error, :execution_source_forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Workout execution source is not authorized"})
  end

  def call(conn, {:error, :execution_source_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Workout execution source does not match the workout"})
  end

  def call(conn, {:error, :completion_processing_unavailable}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Workout completion processing is temporarily unavailable"})
  end

  def call(conn, {:error, :promotion_code_inactive}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion code is inactive"})
  end

  def call(conn, {:error, :promotion_campaign_inactive}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion campaign is inactive"})
  end

  def call(conn, {:error, :promotion_campaign_not_started}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion campaign has not started"})
  end

  def call(conn, {:error, :promotion_campaign_expired}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion campaign has expired"})
  end

  def call(conn, {:error, :promotion_code_max_redemptions_reached}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Promotion code redemption limit reached"})
  end

  def call(conn, {:error, :package_inactive}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Inactive packages cannot be assigned"})
  end

  def call(conn, {:error, :referral_program_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "A referral program is required"})
  end

  def call(conn, {:error, :referral_program_inactive}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "The referral program is inactive"})
  end

  def call(conn, {:error, :referral_user_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Referral participant was not found"})
  end

  def call(conn, {:error, :referral_membership_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Referral events require the referred user's finance membership"})
  end

  def call(conn, {:error, :referral_referrer_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Referral referrer must be a member or athlete"})
  end

  def call(conn, {:error, :referral_referred_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Referral recipient must be a member or athlete"})
  end

  def call(conn, {:error, :invalid_billing_period}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid billing period"})
  end

  def call(conn, {:error, :promotion_discount_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion discount value is required"})
  end

  def call(conn, {:error, :invalid_promotion_discount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Promotion discount is invalid"})
  end

  def call(conn, {:error, :review_target_required}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Review target id is required for this target type"})
  end

  def call(conn, {:error, :review_target_not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: "Review target was not found"})
  end

  def call(conn, {:error, :review_target_not_completed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Review target must be completed before it can be reviewed"})
  end

  def call(conn, {:error, :review_target_must_be_global}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "This review target type must not include a target id"})
  end

  def call(conn, {:error, :invalid_referral_status_transition}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Invalid referral status transition"})
  end

  def call(conn, {:error, :referral_event_not_approved}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Referral event must be approved before applying rewards"})
  end

  def call(conn, {:error, :recipient_membership_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error:
        "Referral reward recipient needs a finance membership profile before credit can be applied"
    })
  end

  def call(conn, {:error, :injury_already_healed}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Injury report is already healed"})
  end

  def call(conn, {:error, :injury_healed_before_started}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Healed date cannot be before started date"})
  end

  def call(conn, {:error, :injury_target_role_ineligible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Injury reports can only target members or athletes"})
  end

  def call(conn, {:error, :invalid_credit_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Credit amount must be greater than zero"})
  end

  def call(conn, {:error, :invalid_referral_reward_type}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Referral reward type is invalid"})
  end

  def call(conn, {:error, :insufficient_credit_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Insufficient credit balance"})
  end

  def call(conn, {:error, :credit_exceeds_payment_amount}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Credit exceeds remaining payment amount"})
  end

  def call(conn, {:error, :payment_not_creditable}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Credit can only be applied to paid or pending payments"})
  end

  def call(conn, {:error, :payment_not_reversible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Only paid or waived payments can be reversed"})
  end

  def call(conn, {:error, :invalid_payment_reversal_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Payment reversal amount must be greater than zero"})
  end

  def call(conn, {:error, :payment_reversal_exceeds_payment_amount}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Payment reversal exceeds remaining payment amount"})
  end

  def call(conn, {:error, :credit_entry_not_reversible}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Only applied credit entries can be reversed"})
  end

  def call(conn, {:error, :credit_reversal_exceeds_application}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Credit reversal exceeds remaining applied credit"})
  end

  def call(conn, {:error, :credit_exceeds_invoice_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Credit exceeds remaining invoice balance"})
  end

  def call(conn, {:error, :invoice_not_issued}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Invoice must be issued before allocations can be applied"})
  end

  def call(conn, {:error, :invoice_already_paid}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Invoice is already paid"})
  end

  def call(conn, {:error, :invoice_void}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Invoice is void"})
  end

  def call(conn, {:error, :invoice_has_allocations}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Invoice has payments or credits and cannot be voided"})
  end

  def call(conn, {:error, :finance_entitlement_blocked}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Finance entitlement blocked"})
  end

  def call(conn, {:error, :finance_profile_missing}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: %{code: "finance_profile_missing", message: "Finance profile required"}})
  end

  def call(conn, {:error, :finance_entitlement_plan_missing}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{
        code: "finance_entitlement_plan_missing",
        message: "The active package has no enforceable entitlement plan"
      }
    })
  end

  def call(conn, {:error, :finance_channel_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{code: "finance_channel_not_included", message: "Package channel not included"}
    })
  end

  def call(conn, {:error, :finance_capability_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{
        code: "finance_capability_not_included",
        message: "Package capability not included"
      }
    })
  end

  def call(conn, {:error, :finance_allowance_not_included}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{code: "finance_allowance_not_included", message: "Package allowance not included"}
    })
  end

  def call(conn, {:error, :finance_allowance_exhausted, details}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      error: %{
        code: "finance_allowance_exhausted",
        message: "Package allowance exhausted",
        details: details
      }
    })
  end

  def call(conn, {:error, :invalid_allowance_grant}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{code: "invalid_allowance_grant", message: "Allowance extension is invalid"}
    })
  end

  def call(conn, {:error, :finance_entitlement_inactive}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Finance entitlement inactive"})
  end

  def call(conn, {:error, :payment_exceeds_invoice_balance}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Payment exceeds remaining invoice balance"})
  end

  def call(conn, {:error, :invalid_payment_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Payment amount must be greater than zero"})
  end

  def call(conn, {:error, :duplicate_renewal_invoice}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Renewal invoice already exists for this service period"})
  end

  def call(conn, {:error, :invalid_invoice_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invoice amount must be greater than zero"})
  end

  def call(conn, {:error, :invalid_invoice_line_amount}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invoice line amounts are invalid"})
  end

  def call(conn, {:error, :invoice_line_discount_exceeds_subtotal}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invoice line discount cannot exceed the line subtotal"})
  end

  def call(conn, {:error, :invalid_renewal_period}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Custom renewals require a valid service period end date"})
  end

  def call(conn, {:error, :self_referral_not_allowed}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Self referrals are not allowed"})
  end

  def call(conn, {:error, :referral_membership_user_mismatch}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Referral membership must belong to the referred user"})
  end

  def call(conn, {:error, :referral_reward_already_exists}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Referral reward already exists for this event"})
  end

  def call(conn, {:error, {:membership_mismatch, _field}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Finance record belongs to a different membership"})
  end

  def call(conn, {:error, :invalid_date}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Bad request"})
  end

  def call(conn, {:error, :invalid_cursor}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid pagination cursor"})
  end

  def call(conn, {:error, :invalid_athletes}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Assigned workouts may target athlete users only"})
  end

  def call(conn, {:error, :workout_reassignment_not_supported}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error:
        "Assigned workout edits keep the workout template fixed; assign a different workout from the workout library"
    })
  end

  def call(conn, {:error, :workout_not_found}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Workout not found"})
  end

  def call(conn, {:error, {:substitution_failed, _}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Workout substitution failed"})
  end

  def call(conn, {:error, :last_admin}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Cannot demote the last admin"})
  end

  def call(conn, {:error, :workout_not_published}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Target workout is not published"})
  end

  def call(conn, {:error, :already_published}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Workout is already published"})
  end

  def call(conn, {:error, :no_sections}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Workout must have at least one section before publishing"})
  end

  def call(conn, {:error, :invalid_scale_level}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Invalid scale level"})
  end

  def call(conn, {:error, :already_completed}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Execution already completed"})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Forbidden"})
  end

  def call(conn, {:error, :slot_full}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Slot is full"})
  end

  def call(conn, {:error, :slot_in_past}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Slot is in the past"})
  end

  def call(conn, {:error, :already_booked}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "User already booked this slot"})
  end

  def call(conn, {:error, :booking_not_pending}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "Booking is no longer pending"})
  end

  def call(conn, {:error, :active_challenge_limit_reached}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "A maximum of 3 overlapping active challenges is allowed"})
  end

  def call(conn, {:error, :leaderboard_refresh_failed}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Leaderboard update is temporarily unavailable"})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: "Unexpected server error"})
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
