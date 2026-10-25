# NutriFit automated test report

Generated: 2026-10-23 00:28
Result: **77 passed, 0 failed, 77 total**

| Test file | Passed | Failed |
|---|---|---|
| test_allocation | 9 | 0 |
| test_evaluation | 4 | 0 |
| test_fake_firestore | 3 | 0 |
| test_foods | 8 | 0 |
| test_messages | 4 | 0 |
| test_missions | 9 | 0 |
| test_nutrition_api | 14 | 0 |
| test_online_recipes | 7 | 0 |
| test_optimizer | 14 | 0 |
| test_profile | 5 | 0 |

## All test cases

| File | Test case | Result |
|---|---|---|
| test_allocation | test_remaining_is_floored_at_zero_but_over_target_is_kept_elsewhere | PASS |
| test_allocation | test_skipped_breakfast_lunch_first_meal_uses_full_day_remaining | PASS |
| test_allocation | test_yes_reserves_part_for_later_meals | PASS |
| test_allocation | test_not_sure_is_between_yes_and_no | PASS |
| test_allocation | test_no_still_enforces_realistic_portion_limit | PASS |
| test_allocation | test_no_gives_all_remaining_when_it_fits_one_meal | PASS |
| test_allocation | test_everything_reached_allocates_nothing | PASS |
| test_allocation | test_config_is_adjustable | PASS |
| test_allocation | test_bad_inputs | PASS |
| test_evaluation | test_sus_known_reference_scores | PASS |
| test_evaluation | test_sus_rejects_bad_answers | PASS |
| test_evaluation | test_satisfaction_and_task_completion | PASS |
| test_evaluation | test_summary_is_empty_without_real_data_and_endpoints_record_results | PASS |
| test_fake_firestore | test_subcollections_are_isolated_per_parent_document | PASS |
| test_fake_firestore | test_where_query_filters_correctly | PASS |
| test_fake_firestore | test_document_get_reflects_updates | PASS |
| test_foods | test_parse_usda_keeps_valid_rows_only | PASS |
| test_foods | test_parse_off_normalises_and_skips_incomplete | PASS |
| test_foods | test_search_survives_one_source_failing | PASS |
| test_foods | test_log_food_scales_by_grams_and_counts_toward_today | PASS |
| test_foods | test_log_food_rejects_unrealistic_values | PASS |
| test_foods | test_parse_off_accepts_new_search_service_shape | PASS |
| test_foods | test_off_falls_back_to_older_endpoint | PASS |
| test_foods | test_parse_off_handles_list_and_dict_fields | PASS |
| test_messages | test_client_and_coach_can_chat_and_unread_counts_update | PASS |
| test_messages | test_empty_message_rejected | PASS |
| test_messages | test_user_cannot_open_someone_elses_thread | PASS |
| test_messages | test_requires_auth | PASS |
| test_missions | test_gallery_source_is_rejected | PASS |
| test_missions | test_stale_photo_is_rejected | PASS |
| test_missions | test_blank_photo_is_not_accepted | PASS |
| test_missions | test_garbage_bytes_rejected | PASS |
| test_missions | test_good_photo_accepted_and_duplicate_blocked | PASS |
| test_missions | test_mission_state_has_three_criteria_and_coach_sees_it | PASS |
| test_missions | test_mission_fails_without_photos | PASS |
| test_missions | test_ai_food_check_rejects_non_food_and_wrong_dish | PASS |
| test_missions | test_ai_food_check_outage_blocks_instead_of_approving | PASS |
| test_nutrition_api | test_optimize_preview_does_not_change_totals | PASS |
| test_nutrition_api | test_planned_meal_is_not_counted_until_confirmed_and_confirm_updates_remaining | PASS |
| test_nutrition_api | test_duplicate_submission_is_ignored | PASS |
| test_nutrition_api | test_edit_and_delete_recalculate_totals | PASS |
| test_nutrition_api | test_over_target_stays_visible_while_remaining_is_zero | PASS |
| test_nutrition_api | test_client_cannot_send_macros_or_foreign_ingredients_or_bad_weights | PASS |
| test_nutrition_api | test_target_change_applies_to_next_optimisation_but_history_keeps_old_target | PASS |
| test_nutrition_api | test_adherence_thresholds_boundaries | PASS |
| test_nutrition_api | test_adherence_rate_and_no_record_days_are_separate | PASS |
| test_nutrition_api | test_one_nutrient_out_of_range_breaks_adherence_and_planned_meals_never_count | PASS |
| test_nutrition_api | test_30_day_period_supported | PASS |
| test_nutrition_api | test_coach_sees_only_own_client_with_unified_numbers_and_can_change_targets | PASS |
| test_nutrition_api | test_regression_existing_features_still_work | PASS |
| test_nutrition_api | test_suggestions_prefer_recipes_that_fit_what_is_left | PASS |
| test_online_recipes | test_convert_makes_per_serving_recipe | PASS |
| test_online_recipes | test_convert_skips_recipes_missing_data | PASS |
| test_online_recipes | test_online_endpoint_saves_recipe_and_it_can_be_scaled | PASS |
| test_online_recipes | test_online_endpoint_reports_unavailable | PASS |
| test_online_recipes | test_local_search_matches_ingredients_and_all_words | PASS |
| test_online_recipes | test_builtin_recipes_have_cooking_steps | PASS |
| test_online_recipes | test_add_recipes_restores_missing_builtins_without_touching_others | PASS |
| test_optimizer | test_recipe_totals_match_hand_calculation | PASS |
| test_optimizer | test_objective_matches_formula_by_hand | PASS |
| test_optimizer | test_reachable_target_is_met_exactly_and_ingredients_differ_individually | PASS |
| test_optimizer | test_beats_uniform_scaling_on_macro_match | PASS |
| test_optimizer | test_limits_fixed_and_nonnegative_respected | PASS |
| test_optimizer | test_infeasible_target_returns_closest_with_explanation | PASS |
| test_optimizer | test_zero_targets_are_stable | PASS |
| test_optimizer | test_boundary_all_ingredients_at_minimum_for_tiny_target | PASS |
| test_optimizer | test_reproducible_for_same_inputs | PASS |
| test_optimizer | test_invalid_inputs_rejected | PASS |
| test_optimizer | test_uniform_fallback_is_labelled_and_bounded | PASS |
| test_optimizer | test_missing_or_invalid_ingredient_data_is_reported_not_invented | PASS |
| test_optimizer | test_reference_data_is_internally_consistent | PASS |
| test_optimizer | test_all_builtin_recipes_are_complete_and_totals_consistent | PASS |
| test_profile | test_me_hides_internal_fields | PASS |
| test_profile | test_update_profile_and_validation | PASS |
| test_profile | test_preferences_roundtrip_and_push_filter | PASS |
| test_profile | test_my_coach | PASS |
| test_profile | test_delete_account_removes_data_and_unlinks_nothing_else | PASS |
