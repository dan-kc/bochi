use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_authenticated_post_request_raw, make_unauthenticated_get_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::{json, Value};

async fn signed_in_token(email: String) -> String {
    let password = "password123";
    register_user(&email, password).await;
    get_access_token_for_user(&email, password).await
}

#[tokio::test]
async fn test_trailing_slash_sync_uses_same_authenticated_route() {
    // A trailing slash should still reach the sync endpoint and enforce auth,
    // not fall through as an unrelated 404.
    let (status, json) = make_unauthenticated_get_request("/api/v1/sync/").await;

    assert_eq!(status, StatusCode::UNAUTHORIZED, "Response: {:?}", json);
}

async fn link_lifetime_premium(access_token: &str, original_transaction_id: &str) {
    std::env::set_var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS", "true");

    let (status, json) = make_authenticated_post_request(
        access_token,
        "/auth/link-apple-subscription",
        json!({
            "transactionId": original_transaction_id,
            "originalTransactionId": original_transaction_id,
            "productId": "lifetime.membership",
            "environment": "xcode",
            "subscriptionExpiresAt": null
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", json);
    assert_eq!(json.get("isEntitled").and_then(|v| v.as_bool()), Some(true));
}

fn upsert_task_operation(payload: Value, base_record_revision: Option<i64>) -> Value {
    let mut payload = payload;
    let payload_object = payload
        .as_object_mut()
        .expect("task test payloads must be JSON objects");
    payload_object
        .entry("pinned".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("hidden".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("timerMode".to_string())
        .or_insert(Value::Null);
    payload_object
        .entry("timerId".to_string())
        .or_insert(Value::Null);

    json!({
        "operationId": uuid::Uuid::new_v4().to_string(),
        "kind": "upsertTask",
        "baseRecordRevision": base_record_revision,
        "payload": payload
    })
}

fn upsert_recurring_task_operation(payload: Value, base_record_revision: Option<i64>) -> Value {
    let mut payload = payload;
    let payload_object = payload
        .as_object_mut()
        .expect("recurring task test payloads must be JSON objects");
    payload_object
        .entry("pinned".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("hidden".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("timerMode".to_string())
        .or_insert(Value::Null);
    payload_object
        .entry("timerId".to_string())
        .or_insert(Value::Null);

    json!({
        "operationId": uuid::Uuid::new_v4().to_string(),
        "kind": "upsertRecurringTask",
        "baseRecordRevision": base_record_revision,
        "payload": payload
    })
}

fn upsert_reward_operation(payload: Value, base_record_revision: Option<i64>) -> Value {
    let mut payload = payload;
    let payload_object = payload
        .as_object_mut()
        .expect("reward test payloads must be JSON objects");
    payload_object
        .entry("pinned".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("hidden".to_string())
        .or_insert(json!(false));
    payload_object
        .entry("timerMode".to_string())
        .or_insert(Value::Null);
    payload_object
        .entry("timerId".to_string())
        .or_insert(Value::Null);

    json!({
        "operationId": uuid::Uuid::new_v4().to_string(),
        "kind": "upsertReward",
        "baseRecordRevision": base_record_revision,
        "payload": payload
    })
}

fn sync_operation(kind: &str, payload: Value, base_record_revision: Option<i64>) -> Value {
    json!({
        "operationId": uuid::Uuid::new_v4().to_string(),
        "kind": kind,
        "baseRecordRevision": base_record_revision,
        "payload": payload
    })
}

#[tokio::test]
async fn test_sync_timer_uses_intervals_contract() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_timer_uses_intervals_contract
    ))
    .await;
    let timer_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "operations": [sync_operation("upsertTimer", json!({
            "id": timer_id,
            "name": "Pomodoro",
            "intervals": [
                { "name": "Focus", "durationSeconds": 1500 },
                { "name": "Break", "durationSeconds": 300 }
            ],
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null
        }), None)]
    });

    let (status, response) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK, "Response: {:?}", response);
    assert_eq!(response["timers"][0]["id"], timer_id);
    assert_eq!(response["timers"][0]["intervals"][0]["name"], "Focus");
    assert_eq!(
        response["timers"][0]["intervals"][1]["durationSeconds"],
        300
    );
    assert!(response["timers"][0].get("sections").is_none());
}

#[tokio::test]
async fn test_sync_timer_rejects_legacy_sections_field() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_timer_rejects_legacy_sections_field
    ))
    .await;

    let body = json!({
        "operations": [sync_operation("upsertTimer", json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Legacy Timer",
            "sections": [
                { "name": "Focus", "durationSeconds": 1500 }
            ],
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null
        }), None)]
    });

    let (status, response) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", response);
}

fn upsert_task_operation_with_id(
    operation_id: &str,
    task_id: &str,
    name: &str,
    updated_at: &str,
    base_price: i32,
    base_record_revision: Option<i64>,
) -> Value {
    json!({
        "operationId": operation_id,
        "kind": "upsertTask",
        "baseRecordRevision": base_record_revision,
        "payload": {
            "id": task_id,
            "name": name,
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": updated_at,
            "deletedAt": null,
            "basePrice": base_price,
            "dueDate": null,
            "pinned": false,
            "hidden": false,
            "timerMode": null,
            "timerId": null
        }
    })
}

struct LostResponseMixedRetryScenario {
    edited_task_id: String,
    mixed_retry_body: Value,
    first_edited_revision: i64,
}

async fn create_lost_response_mixed_retry_scenario(
    access_token: &str,
) -> LostResponseMixedRetryScenario {
    let edited_task_id = uuid::Uuid::new_v4().to_string();
    let unchanged_task_id = uuid::Uuid::new_v4().to_string();
    let first_edit_operation_id = uuid::Uuid::new_v4().to_string();
    let unchanged_operation_id = uuid::Uuid::new_v4().to_string();
    let unchanged_task_operation = upsert_task_operation_with_id(
        &unchanged_operation_id,
        &unchanged_task_id,
        "Unchanged task",
        "2025-01-01T09:05:00",
        120,
        None,
    );
    let first_body = json!({
        "operations": [
            upsert_task_operation_with_id(
                &first_edit_operation_id,
                &edited_task_id,
                "Task before lost response",
                "2025-01-01T09:00:00",
                100,
                None
            ),
            unchanged_task_operation.clone()
        ]
    });

    let (first_status, first_json) =
        make_authenticated_post_request(access_token, "/api/v1/sync", first_body).await;
    assert_eq!(first_status, StatusCode::OK, "Response: {:?}", first_json);
    let first_edited_revision = first_json["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["id"] == edited_task_id)
        .unwrap()["serverRevision"]
        .as_i64()
        .unwrap();

    let newer_edit_operation_id = uuid::Uuid::new_v4().to_string();
    let mixed_retry_body = json!({
        "operations": [
            upsert_task_operation_with_id(
                &newer_edit_operation_id,
                &edited_task_id,
                "Task edited after lost response",
                "2025-01-01T09:10:00",
                175,
                None
            ),
            unchanged_task_operation
        ]
    });

    LostResponseMixedRetryScenario {
        edited_task_id,
        mixed_retry_body,
        first_edited_revision,
    }
}

#[tokio::test]
async fn test_sync_pull_requires_authentication() {
    let (status, _) = make_unauthenticated_get_request("/api/v1/sync").await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_sync_push_and_pull_round_trips_base_prices() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_and_pull_round_trips_base_prices
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let recurring_task_id = uuid::Uuid::new_v4().to_string();
    let second_recurring_task_id = uuid::Uuid::new_v4().to_string();
    let recurring_reward_id = uuid::Uuid::new_v4().to_string();
    let one_off_reward_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "operations": [
            upsert_task_operation(json!({
            "id": task_id,
            "name": "Submit report",
            "description": "One-off task",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 275,
            "dueDate": "2025-01-02T09:00:00"
        }), None),
            upsert_recurring_task_operation(json!({
            "id": recurring_task_id,
            "name": "Deep work",
            "description": "Recurring task surfaced as recurringTask",
            "createdAt": "2025-01-01T09:10:00",
            "updatedAt": "2025-01-01T09:10:00",
            "deletedAt": null,
            "basePrice": 120,
            "minDailyFrequency": 1.0,
            "lockoutDurationSeconds": 3600
        }), None),
            upsert_recurring_task_operation(json!({
            "id": second_recurring_task_id,
            "name": "Walk",
            "description": "Recurring recurringTask",
            "createdAt": "2025-01-01T09:20:00",
            "updatedAt": "2025-01-01T09:20:00",
            "deletedAt": null,
            "minDailyFrequency": 2.0,
            "basePrice": 95,
            "lockoutDurationSeconds": null
        }), None),
            upsert_reward_operation(json!({
            "id": recurring_reward_id,
            "recurring": true,
            "name": "Coffee",
            "description": "Recurring reward",
            "createdAt": "2025-01-01T09:30:00",
            "updatedAt": "2025-01-01T09:30:00",
            "deletedAt": null,
            "maxDailyFrequency": 1.0,
            "basePrice": 450,
            "lockoutDurationSeconds": 600
        }), None),
            upsert_reward_operation(json!({
            "id": one_off_reward_id,
            "recurring": false,
            "name": "New keyboard",
            "description": "One-off reward",
            "createdAt": "2025-01-01T09:40:00",
            "updatedAt": "2025-01-01T09:40:00",
            "deletedAt": null,
            "basePrice": 2500
        }), None)
        ]
    });

    let (push_status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(push_status, StatusCode::OK, "Response: {:?}", push_json);
    assert_eq!(push_json["tasks"][0]["basePrice"], 275);
    assert!(push_json["recurringTasks"]
        .as_array()
        .unwrap()
        .iter()
        .any(
            |recurring_task| recurring_task["id"] == second_recurring_task_id
                && recurring_task["basePrice"] == 95
        ));
    assert_eq!(push_json["rewards"][0]["basePrice"], 450);
    assert!(push_json.get("specialOffers").is_none());
    assert!(push_json.get("generalDifficulty").is_none());

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(pull_status, StatusCode::OK, "Response: {:?}", pull_json);
    assert!(pull_json["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .any(|task| task["id"] == task_id && task["basePrice"] == 275));
    assert!(pull_json["recurringTasks"]
        .as_array()
        .unwrap()
        .iter()
        .any(
            |recurring_task| recurring_task["id"] == second_recurring_task_id
                && recurring_task["basePrice"] == 95
        ));
    assert!(pull_json["recurringTasks"]
        .as_array()
        .unwrap()
        .iter()
        .any(|recurring_task| recurring_task["id"] == recurring_task_id
            && recurring_task["basePrice"] == 120));
    assert!(pull_json["rewards"]
        .as_array()
        .unwrap()
        .iter()
        .any(|reward| reward["id"] == recurring_reward_id && reward["basePrice"] == 450));
    assert!(pull_json["rewards"]
        .as_array()
        .unwrap()
        .iter()
        .any(|reward| reward["id"] == one_off_reward_id
            && reward["recurring"] == false
            && reward["basePrice"] == 2500));
    assert!(pull_json.get("specialOffers").is_none());
    assert!(pull_json.get("generalDifficulty").is_none());
}

#[tokio::test]
async fn test_sync_push_rejects_negative_base_price() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_negative_base_price
    ))
    .await;

    let body = json!({
        "operations": [upsert_task_operation(json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Invalid task",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": -1
        }), None)]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);
}

#[tokio::test]
async fn test_sync_push_rejects_numbers_above_i32_contract() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_numbers_above_i32_contract
    ))
    .await;

    let body = json!({
        "operations": [upsert_task_operation(json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Too expensive",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": i64::from(i32::MAX) + 1
        }), None)]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_sync_push_accepts_trade_updated_at_from_ios() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_accepts_trade_updated_at_from_ios
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "Complete with trade",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), None),
            sync_operation("upsertTrade", json!({
            "id": trade_id,
            "taskId": task_id,
            "recurringTaskId": null,
            "rewardId": null,
            "sourceName": "Complete with trade",
            "amount": 100,
            "vaultAmountMicro": null,
            "adjustmentBaseAmount": 100,
            "oneTimeAdjustmentMultiplier": null,
            "tradeKind": "taskCompletion",
            "vaultInterestHour": null,
            "createdAt": "2025-01-01T09:05:00",
            "updatedAt": "2025-01-01T09:05:00",
            "deletedAt": null,
            "refundsTradeId": null
        }), None)]
    });

    let (push_status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(push_status, StatusCode::OK, "Response: {:?}", push_json);
    assert!(push_json["trades"]
        .as_array()
        .unwrap()
        .iter()
        .any(|trade| trade["id"] == trade_id && trade["amount"] == 100));
}

#[tokio::test]
async fn test_sync_push_allows_reusing_deleted_tag_name() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_allows_reusing_deleted_tag_name
    ))
    .await;

    let deleted_tag_id = uuid::Uuid::new_v4().to_string();
    let replacement_tag_id = uuid::Uuid::new_v4().to_string();
    let create_deleted_tag = json!({
        "operations": [sync_operation("upsertTag", json!({
            "id": deleted_tag_id,
            "name": "Health",
            "colorHex": "#FF0000",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": "2025-01-01T10:00:00"
        }), None)]
    });

    let (deleted_status, deleted_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", create_deleted_tag).await;
    assert_eq!(
        deleted_status,
        StatusCode::OK,
        "Response: {:?}",
        deleted_json
    );

    let recreate_tag = json!({
        "operations": [sync_operation("upsertTag", json!({
            "id": replacement_tag_id,
            "name": "Health",
            "colorHex": "#00FF00",
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": null
        }), None)]
    });

    let (recreate_status, recreate_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", recreate_tag).await;

    assert_eq!(
        recreate_status,
        StatusCode::OK,
        "Response: {:?}",
        recreate_json
    );
    assert!(recreate_json["tags"].as_array().unwrap().iter().any(|tag| {
        tag["id"] == replacement_tag_id && tag["name"] == "Health" && tag["deletedAt"].is_null()
    }));
}

#[tokio::test]
async fn test_sync_push_rejects_removed_pricing_fields() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_removed_pricing_fields
    ))
    .await;

    let body = json!({
        "operations": [upsert_task_operation(json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Old task",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "difficultyTier": "medium",
            "durationSeconds": 900,
            "importance": 3
        }), None)]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_ne!(status, StatusCode::OK);
}

#[tokio::test]
async fn test_sync_push_rejects_removed_special_offers_and_general_difficulty() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_removed_special_offers_and_general_difficulty
    ))
    .await;

    let body = json!({
        "generalDifficulty": 5.0,
        "specialOffers": []
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_ne!(status, StatusCode::OK);
}

#[tokio::test]
async fn test_sync_push_rejects_legacy_direct_write_arrays() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_legacy_direct_write_arrays
    ))
    .await;

    let body = json!({
        "timers": [],
        "themePalettes": {
            "main": "sky",
            "accent": "jade"
        }
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_ne!(status, StatusCode::OK);
}

#[tokio::test]
async fn test_sync_push_requires_operations_field() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_requires_operations_field
    ))
    .await;

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", json!({})).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_sync_push_rejects_empty_operations() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_empty_operations
    ))
    .await;

    let (status, json) = make_authenticated_post_request(
        &access_token,
        "/api/v1/sync",
        json!({
            "operations": []
        }),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);
}

#[tokio::test]
async fn test_sync_push_rejects_duplicate_operation_ids_in_same_request() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_duplicate_operation_ids_in_same_request
    ))
    .await;

    let operation_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "operations": [
            upsert_task_operation_with_id(
                &operation_id,
                &uuid::Uuid::new_v4().to_string(),
                "First duplicate operation",
                "2025-01-01T09:00:00",
                100,
                None
            ),
            upsert_task_operation_with_id(
                &operation_id,
                &uuid::Uuid::new_v4().to_string(),
                "Second duplicate operation",
                "2025-01-01T09:05:00",
                120,
                None
            )
        ]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST, "Response: {:?}", json);
}

#[tokio::test]
async fn test_sync_push_rejects_task_payload_missing_required_current_fields() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_rejects_task_payload_missing_required_current_fields
    ))
    .await;

    let body = json!({
        "operations": [{
            "operationId": uuid::Uuid::new_v4().to_string(),
            "kind": "upsertTask",
            "baseRecordRevision": null,
            "payload": {
                "id": uuid::Uuid::new_v4().to_string(),
                "name": "Old client task",
                "description": "",
                "createdAt": "2025-01-01T09:00:00",
                "updatedAt": "2025-01-01T09:00:00",
                "deletedAt": null,
                "basePrice": 100,
                "dueDate": null
            }
        }]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_sync_rejects_stale_task_tag_operation_base_revision() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_rejects_stale_task_tag_operation_base_revision
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();
    let create_body = json!({
        "operations": [
            upsert_task_operation(json!({
                "id": task_id,
                "name": "Tagged task",
                "description": "",
                "createdAt": "2025-01-01T09:00:00",
                "updatedAt": "2025-01-01T09:00:00",
                "deletedAt": null,
                "basePrice": 100
            }), None),
            sync_operation("upsertTag", json!({
                "id": tag_id,
                "name": "Deep work",
                "colorHex": "#123456",
                "createdAt": "2025-01-01T09:00:00",
                "updatedAt": "2025-01-01T09:00:00",
                "deletedAt": null
            }), None),
            sync_operation("upsertTaskTag", json!({
                "taskId": task_id,
                "tagId": tag_id,
                "createdAt": "2025-01-01T09:05:00",
                "updatedAt": "2025-01-01T09:05:00",
                "deletedAt": null
            }), None)
        ]
    });
    let (create_status, create_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", create_body).await;
    assert_eq!(create_status, StatusCode::OK, "Response: {:?}", create_json);
    let base_revision = create_json["taskTags"][0]["serverRevision"]
        .as_i64()
        .unwrap();

    let accepted_delete = json!({
        "operations": [sync_operation("upsertTaskTag", json!({
            "taskId": task_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T09:05:00",
            "updatedAt": "2025-01-01T10:00:00",
            "deletedAt": "2025-01-01T10:00:00"
        }), Some(base_revision))]
    });
    let (accepted_status, accepted_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", accepted_delete).await;
    assert_eq!(
        accepted_status,
        StatusCode::OK,
        "Response: {:?}",
        accepted_json
    );

    let stale_restore = json!({
        "operations": [sync_operation("upsertTaskTag", json!({
            "taskId": task_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T09:05:00",
            "updatedAt": "2099-01-01T09:00:00",
            "deletedAt": null
        }), Some(base_revision))]
    });

    let (stale_status, stale_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", stale_restore).await;

    assert_eq!(
        stale_status,
        StatusCode::CONFLICT,
        "Response: {:?}",
        stale_json
    );
}

#[tokio::test]
async fn test_sync_uses_server_revisions_for_pull_cursors() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_uses_server_revisions_for_pull_cursors
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "Server revision task",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2099-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), None)]
    });

    let (push_status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(push_status, StatusCode::OK, "Response: {:?}", push_json);
    let first_revision = push_json["tasks"][0]["serverRevision"]
        .as_i64()
        .expect("synced rows expose an authoritative server revision");
    let cursor = push_json["serverCursor"]
        .as_str()
        .expect("sync cursor is returned")
        .to_string();
    assert_eq!(cursor, first_revision.to_string());

    let (empty_status, empty_json) =
        make_authenticated_get_request(&access_token, &format!("/api/v1/sync?cursor={cursor}"))
            .await;

    assert_eq!(empty_status, StatusCode::OK, "Response: {:?}", empty_json);
    assert_eq!(
        empty_json["tasks"].as_array().unwrap().len(),
        0,
        "pulling from the accepted revision should not re-send already checkpointed rows"
    );

    let update_body = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "Server revision task renamed",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2000-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), Some(first_revision))]
    });

    let (update_status, update_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", update_body).await;
    assert_eq!(update_status, StatusCode::OK, "Response: {:?}", update_json);
    let second_revision = update_json["tasks"][0]["serverRevision"]
        .as_i64()
        .expect("updated row exposes its new server revision");
    assert!(
        second_revision > first_revision,
        "server revisions must be monotonic regardless of client timestamps"
    );

    let (delta_status, delta_json) =
        make_authenticated_get_request(&access_token, &format!("/api/v1/sync?cursor={cursor}"))
            .await;
    assert_eq!(delta_status, StatusCode::OK, "Response: {:?}", delta_json);
    assert!(delta_json["tasks"].as_array().unwrap().iter().any(|task| {
        task["id"] == task_id
            && task["name"] == "Server revision task renamed"
            && task["serverRevision"] == second_revision
    }));
}

#[tokio::test]
async fn test_sync_rejects_stale_operation_base_revision() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_rejects_stale_operation_base_revision
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let create_body = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "Original",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), None)]
    });
    let (create_status, create_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", create_body).await;
    assert_eq!(create_status, StatusCode::OK, "Response: {:?}", create_json);
    let base_revision = create_json["tasks"][0]["serverRevision"].as_i64().unwrap();

    let first_update = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "First accepted update",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), Some(base_revision))]
    });
    let (first_status, first_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", first_update).await;
    assert_eq!(first_status, StatusCode::OK, "Response: {:?}", first_json);

    let stale_update = json!({
        "operations": [upsert_task_operation(json!({
            "id": task_id,
            "name": "Stale update should not win",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2099-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100
        }), Some(base_revision))]
    });

    let (stale_status, stale_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", stale_update).await;

    assert_eq!(
        stale_status,
        StatusCode::CONFLICT,
        "Response: {:?}",
        stale_json
    );
}

#[tokio::test]
async fn test_sync_checks_recurring_task_operation_base_revision_against_recurring_task_rows() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_checks_recurring_task_operation_base_revision_against_recurring_task_rows
    ))
    .await;

    let recurring_task_id = uuid::Uuid::new_v4().to_string();
    let create_body = json!({
        "operations": [upsert_recurring_task_operation(json!({
            "id": recurring_task_id,
            "name": "Original recurring task",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "minDailyFrequency": 1.0,
            "lockoutDurationSeconds": null
        }), None)]
    });
    let (create_status, create_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", create_body).await;
    assert_eq!(create_status, StatusCode::OK, "Response: {:?}", create_json);
    let base_revision = create_json["recurringTasks"][0]["serverRevision"]
        .as_i64()
        .unwrap();

    let accepted_update = json!({
        "operations": [upsert_recurring_task_operation(json!({
            "id": recurring_task_id,
            "name": "Accepted recurring task update",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "minDailyFrequency": 1.0,
            "lockoutDurationSeconds": null
        }), Some(base_revision))]
    });
    let (accepted_status, accepted_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", accepted_update).await;
    assert_eq!(
        accepted_status,
        StatusCode::OK,
        "Response: {:?}",
        accepted_json
    );

    let stale_update = json!({
        "operations": [upsert_recurring_task_operation(json!({
            "id": recurring_task_id,
            "name": "Stale recurring task update",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2099-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "minDailyFrequency": 1.0,
            "lockoutDurationSeconds": null
        }), Some(base_revision))]
    });

    let (stale_status, stale_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", stale_update).await;

    assert_eq!(
        stale_status,
        StatusCode::CONFLICT,
        "Response: {:?}",
        stale_json
    );
}

#[tokio::test]
async fn test_sync_push_theme_palettes_returns_written_palettes() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_push_theme_palettes_returns_written_palettes
    ))
    .await;

    let body = json!({
        "operations": [{
            "operationId": uuid::Uuid::new_v4().to_string(),
            "kind": "updateThemePalettes",
            "baseRecordRevision": null,
            "payload": {
                "main": "sky",
                "accent": "jade"
            }
        }]
    });

    let (first_status, first_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(first_status, StatusCode::OK, "Response: {:?}", first_json);
    assert_eq!(first_json["themePalettes"]["main"], "sky");
    assert_eq!(first_json["themePalettes"]["accent"], "jade");

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);
    assert_eq!(retry_json["themePalettes"]["main"], "sky");
    assert_eq!(retry_json["themePalettes"]["accent"], "jade");
}

#[tokio::test]
async fn test_sync_reward_purchase_retry_preserves_dependency_baseline() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_reward_purchase_retry_preserves_dependency_baseline
    ))
    .await;
    link_lifetime_premium(
        &access_token,
        "test_sync_reward_purchase_retry_preserves_dependency_baseline",
    )
    .await;

    let recurring_task_id = uuid::Uuid::new_v4().to_string();
    let reward_id = uuid::Uuid::new_v4().to_string();
    let purchase_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "operations": [upsert_recurring_task_operation(json!({
            "id": recurring_task_id,
            "name": "Stretch",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 10,
            "minDailyFrequency": 1.0,
            "lockoutDurationSeconds": null
        }), None),
            upsert_reward_operation(json!({
            "id": reward_id,
            "recurring": true,
            "name": "Watch episode",
            "description": "",
            "createdAt": "2025-01-01T09:05:00",
            "updatedAt": "2025-01-01T09:05:00",
            "deletedAt": null,
            "basePrice": 10,
            "maxDailyFrequency": null,
            "lockoutDurationSeconds": null
        }), None),
            sync_operation("upsertRewardRecurringTaskDependency", json!({
            "rewardId": reward_id,
            "recurringTaskId": recurring_task_id,
            "requiredCompletions": 3,
            "baselineCompletionCount": 0,
            "createdAt": "2025-01-01T09:10:00",
            "updatedAt": "2025-01-01T09:10:00",
            "deletedAt": null
        }), None)]
    });
    let (setup_status, setup_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK, "Response: {:?}", setup_json);

    let initial_completions = json!({
        "operations": (0..3).map(|index| sync_operation("upsertTrade", json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "taskId": null,
            "recurringTaskId": recurring_task_id,
            "rewardId": null,
            "sourceName": "Stretch",
            "amount": 10,
            "vaultAmountMicro": null,
            "adjustmentBaseAmount": 10,
            "oneTimeAdjustmentMultiplier": null,
            "tradeKind": "recurringTaskCompletion",
            "vaultInterestHour": null,
            "createdAt": format!("2025-01-01T10:0{index}:00"),
            "updatedAt": format!("2025-01-01T10:0{index}:00"),
            "deletedAt": null,
            "refundsTradeId": null
        }), None)).collect::<Vec<_>>()
    });
    let (initial_status, initial_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", initial_completions).await;
    assert_eq!(
        initial_status,
        StatusCode::OK,
        "Response: {:?}",
        initial_json
    );

    let purchase_body = json!({
        "operations": [sync_operation("upsertTrade", json!({
            "id": purchase_trade_id,
            "taskId": null,
            "recurringTaskId": null,
            "rewardId": reward_id,
            "sourceName": "Watch episode",
            "amount": -10,
            "vaultAmountMicro": null,
            "adjustmentBaseAmount": 10,
            "oneTimeAdjustmentMultiplier": null,
            "tradeKind": "rewardPurchase",
            "vaultInterestHour": null,
            "createdAt": "2025-01-01T10:10:00",
            "updatedAt": "2025-01-01T10:10:00",
            "deletedAt": null,
            "refundsTradeId": null
        }), None)]
    });
    let (purchase_status, purchase_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", purchase_body.clone()).await;
    assert_eq!(
        purchase_status,
        StatusCode::OK,
        "Response: {:?}",
        purchase_json
    );
    assert!(purchase_json["rewardRecurringTaskDependencies"]
        .as_array()
        .unwrap()
        .iter()
        .any(|dependency| {
            dependency["rewardId"] == reward_id
                && dependency["recurringTaskId"] == recurring_task_id
                && dependency["baselineCompletionCount"] == 3
        }));

    let later_completions = json!({
        "operations": (0..3).map(|index| sync_operation("upsertTrade", json!({
            "id": uuid::Uuid::new_v4().to_string(),
            "taskId": null,
            "recurringTaskId": recurring_task_id,
            "rewardId": null,
            "sourceName": "Stretch",
            "amount": 10,
            "vaultAmountMicro": null,
            "adjustmentBaseAmount": 10,
            "oneTimeAdjustmentMultiplier": null,
            "tradeKind": "recurringTaskCompletion",
            "vaultInterestHour": null,
            "createdAt": format!("2025-01-01T11:0{index}:00"),
            "updatedAt": format!("2025-01-01T11:0{index}:00"),
            "deletedAt": null,
            "refundsTradeId": null
        }), None)).collect::<Vec<_>>()
    });
    let (later_status, later_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", later_completions).await;
    assert_eq!(later_status, StatusCode::OK, "Response: {:?}", later_json);

    // Retrying a purchase after the server committed it must not spend later
    // recurringTask completions by moving the dependency baseline a second time.
    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", purchase_body).await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_status, StatusCode::OK, "Response: {:?}", pull_json);
    assert!(pull_json["rewardRecurringTaskDependencies"]
        .as_array()
        .unwrap()
        .iter()
        .any(|dependency| {
            dependency["rewardId"] == reward_id
                && dependency["recurringTaskId"] == recurring_task_id
                && dependency["baselineCompletionCount"] == 3
        }));
}

#[tokio::test]
async fn test_sync_operations_are_idempotent_by_operation_id() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_operations_are_idempotent_by_operation_id
    ))
    .await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let operation_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "operations": [{
            "operationId": operation_id,
            "kind": "upsertTask",
            "baseRecordRevision": null,
            "payload": {
                "id": task_id,
                "name": "Idempotent task",
                "description": "",
                "createdAt": "2025-01-01T09:00:00",
                "updatedAt": "2025-01-01T09:00:00",
                "deletedAt": null,
                "basePrice": 100,
                "dueDate": null,
                "pinned": false,
                "hidden": false,
                "timerMode": null,
                "timerId": null
            }
        }]
    });

    let (first_status, first_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(first_status, StatusCode::OK, "Response: {:?}", first_json);
    let first_revision = first_json["tasks"][0]["serverRevision"].as_i64().unwrap();

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);
    assert_eq!(
        retry_json["tasks"][0]["serverRevision"].as_i64().unwrap(),
        first_revision,
        "retrying the same operation must return the already accepted server state without writing a new revision"
    );
    assert_eq!(
        retry_json["serverCursor"].as_str().unwrap(),
        first_revision.to_string()
    );
}

#[tokio::test]
async fn test_sync_operation_batches_are_idempotent_by_operation_ids() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_operation_batches_are_idempotent_by_operation_ids
    ))
    .await;

    let first_task_id = uuid::Uuid::new_v4().to_string();
    let second_task_id = uuid::Uuid::new_v4().to_string();
    let first_operation_id = uuid::Uuid::new_v4().to_string();
    let second_operation_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "operations": [{
            "operationId": first_operation_id,
            "kind": "upsertTask",
            "baseRecordRevision": null,
            "payload": {
                "id": first_task_id,
                "name": "First idempotent task",
                "description": "",
                "createdAt": "2025-01-01T09:00:00",
                "updatedAt": "2025-01-01T09:00:00",
                "deletedAt": null,
                "basePrice": 100,
                "dueDate": null,
                "pinned": false,
                "hidden": false,
                "timerMode": null,
                "timerId": null
            }
        }, {
            "operationId": second_operation_id,
            "kind": "upsertTask",
            "baseRecordRevision": null,
            "payload": {
                "id": second_task_id,
                "name": "Second idempotent task",
                "description": "",
                "createdAt": "2025-01-01T09:05:00",
                "updatedAt": "2025-01-01T09:05:00",
                "deletedAt": null,
                "basePrice": 120,
                "dueDate": null,
                "pinned": false,
                "hidden": false,
                "timerMode": null,
                "timerId": null
            }
        }]
    });

    let (first_status, first_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(first_status, StatusCode::OK, "Response: {:?}", first_json);
    let first_cursor = first_json["serverCursor"].as_str().unwrap().to_string();

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);
    assert_eq!(
        retry_json["serverCursor"].as_str().unwrap(),
        first_cursor,
        "retrying a committed batch must return the cached response instead of re-checking stale bases"
    );
    assert_eq!(retry_json["tasks"].as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn test_sync_mixed_retry_after_lost_response_accepts_newer_edit() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_mixed_retry_after_lost_response_accepts_newer_edit
    ))
    .await;
    let scenario = create_lost_response_mixed_retry_scenario(&access_token).await;

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", scenario.mixed_retry_body)
            .await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);

    let retried_task = retry_json["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["id"] == scenario.edited_task_id)
        .unwrap();
    assert_eq!(retried_task["name"], "Task edited after lost response");
    assert!(
        retried_task["serverRevision"].as_i64().unwrap() > scenario.first_edited_revision,
        "the follow-up edit should commit after the server recognizes the sibling operation from the lost response"
    );
}

#[tokio::test]
async fn test_sync_recovered_mixed_retry_is_itself_idempotent() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_recovered_mixed_retry_is_itself_idempotent
    ))
    .await;
    let scenario = create_lost_response_mixed_retry_scenario(&access_token).await;

    let (recovery_status, recovery_json) = make_authenticated_post_request(
        &access_token,
        "/api/v1/sync",
        scenario.mixed_retry_body.clone(),
    )
    .await;
    assert_eq!(
        recovery_status,
        StatusCode::OK,
        "Response: {:?}",
        recovery_json
    );
    let recovery_cursor = recovery_json["serverCursor"].as_str().unwrap().to_string();
    let recovery_revision = recovery_json["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["id"] == scenario.edited_task_id)
        .unwrap()["serverRevision"]
        .as_i64()
        .unwrap();

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", scenario.mixed_retry_body)
            .await;
    assert_eq!(retry_status, StatusCode::OK, "Response: {:?}", retry_json);
    assert_eq!(
        retry_json["serverCursor"].as_str().unwrap(),
        recovery_cursor,
        "retrying the recovery request should return the latest accepted response, even when its operations span cached batches"
    );
    assert_eq!(
        retry_json["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|task| task["id"] == scenario.edited_task_id)
            .unwrap()["serverRevision"]
            .as_i64()
            .unwrap(),
        recovery_revision,
        "retrying the recovery request must not write another revision"
    );
}

#[tokio::test]
async fn test_sync_mixed_retry_does_not_use_cursor_delta_as_write_base() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_mixed_retry_does_not_use_cursor_delta_as_write_base
    ))
    .await;

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_status, StatusCode::OK, "Response: {:?}", pull_json);
    let old_cursor = pull_json["serverCursor"].as_str().unwrap();

    let remotely_changed_task_id = uuid::Uuid::new_v4().to_string();
    let remote_operation_id = uuid::Uuid::new_v4().to_string();
    let remote_body = json!({
        "operations": [upsert_task_operation_with_id(
            &remote_operation_id,
            &remotely_changed_task_id,
            "Remote task",
            "2025-01-01T09:00:00",
            100,
            None
        )]
    });
    let (remote_status, remote_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", remote_body).await;
    assert_eq!(remote_status, StatusCode::OK, "Response: {:?}", remote_json);

    let acknowledged_task_id = uuid::Uuid::new_v4().to_string();
    let acknowledged_operation_id = uuid::Uuid::new_v4().to_string();
    let acknowledged_operation = upsert_task_operation_with_id(
        &acknowledged_operation_id,
        &acknowledged_task_id,
        "Acknowledged task",
        "2025-01-01T09:05:00",
        120,
        None,
    );
    let response_with_cursor_delta = json!({
        "baseCursor": old_cursor,
        "operations": [acknowledged_operation.clone()]
    });
    let (acknowledged_status, acknowledged_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", response_with_cursor_delta)
            .await;
    assert_eq!(
        acknowledged_status,
        StatusCode::OK,
        "Response: {:?}",
        acknowledged_json
    );
    assert!(
        acknowledged_json["tasks"]
            .as_array()
            .unwrap()
            .iter()
            .any(|task| task["id"] == remotely_changed_task_id),
        "the cached response should contain the remote cursor-delta task that must not become recovery evidence"
    );

    let stale_overwrite_operation_id = uuid::Uuid::new_v4().to_string();
    let mixed_retry_body = json!({
        "operations": [
            upsert_task_operation_with_id(
                &stale_overwrite_operation_id,
                &remotely_changed_task_id,
                "Stale overwrite",
                "2025-01-01T09:10:00",
                175,
                None
            ),
            acknowledged_operation
        ]
    });

    let (retry_status, retry_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", mixed_retry_body).await;
    assert_eq!(
        retry_status,
        StatusCode::CONFLICT,
        "Response: {:?}",
        retry_json
    );
}

#[tokio::test]
async fn test_sync_rejects_stale_reward_operation_base_revision() {
    let access_token = signed_in_token(generate_email_from_fn!(
        test_sync_rejects_stale_reward_operation_base_revision
    ))
    .await;

    let reward_id = uuid::Uuid::new_v4().to_string();
    let create_body = json!({
        "operations": [upsert_reward_operation(json!({
            "id": reward_id,
            "recurring": true,
            "name": "Original reward",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "maxDailyFrequency": null,
            "lockoutDurationSeconds": null
        }), None)]
    });
    let (create_status, create_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", create_body).await;
    assert_eq!(create_status, StatusCode::OK, "Response: {:?}", create_json);
    let base_revision = create_json["rewards"][0]["serverRevision"]
        .as_i64()
        .unwrap();

    let accepted_update = json!({
        "operations": [upsert_reward_operation(json!({
            "id": reward_id,
            "recurring": true,
            "name": "Accepted reward update",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "maxDailyFrequency": null,
            "lockoutDurationSeconds": null
        }), Some(base_revision))]
    });
    let (accepted_status, accepted_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", accepted_update).await;
    assert_eq!(
        accepted_status,
        StatusCode::OK,
        "Response: {:?}",
        accepted_json
    );

    let stale_update = json!({
        "operations": [upsert_reward_operation(json!({
            "id": reward_id,
            "recurring": true,
            "name": "Stale reward update",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2099-01-01T09:00:00",
            "deletedAt": null,
            "basePrice": 100,
            "maxDailyFrequency": null,
            "lockoutDurationSeconds": null
        }), Some(base_revision))]
    });

    let (stale_status, stale_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", stale_update).await;

    assert_eq!(
        stale_status,
        StatusCode::CONFLICT,
        "Response: {:?}",
        stale_json
    );
}
