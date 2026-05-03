use crate::common::{
    get_access_token_for_user, make_authenticated_get_request, make_authenticated_post_request,
    make_authenticated_post_request_raw, make_unauthenticated_get_request,
    make_unauthenticated_post_request, register_user,
};
use crate::generate_email_from_fn;
use axum::http::StatusCode;
use serde_json::{json, Value};

// ============================================================================
// Sync Pull (GET /api/v1/sync) Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_returns_all_entity_types() {
    let email = generate_email_from_fn!(test_sync_pull_returns_all_entity_types);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();
    let task_trade_id = uuid::Uuid::new_v4().to_string();
    let dependent_task_id = uuid::Uuid::new_v4().to_string();
    let task_dependency_created_at = "2025-01-01T09:15:00";
    let habit_dependency_created_at = "2025-01-01T09:20:00";

    // Create a habit first
    let habit_body = json!({
        "name": "Test Habit",
        "description": "A test habit"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap();

    // Create a trade for that habit using POST /api/v1/sync
    let trade_id = uuid::Uuid::new_v4().to_string();
    let sync_body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Submit report",
            "description": "Finish the monthly report",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "difficultyTier": "light",
            "durationSeconds": 600,
            "commitment": 2,
            "dueDate": "2025-01-02T09:00:00"
        }, {
            "id": dependent_task_id,
            "name": "Send report",
            "description": "Only after the draft is done",
            "createdAt": "2025-01-01T09:05:00",
            "updatedAt": "2025-01-01T09:05:00",
            "difficultyTier": "medium"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Work",
            "colorHex": "#112233",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00"
        }],
        "taskTags": [{
            "taskId": task_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00"
        }],
        "taskTaskDependencies": [{
            "taskId": dependent_task_id,
            "dependsOnTaskId": task_id,
            "createdAt": task_dependency_created_at,
            "updatedAt": task_dependency_created_at
        }],
        "taskHabitDependencies": [{
            "taskId": dependent_task_id,
            "habitId": habit_id,
            "requiredCompletions": 2,
            "baselineCompletionCount": 1,
            "createdAt": habit_dependency_created_at,
            "updatedAt": habit_dependency_created_at
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }, {
            "id": task_trade_id,
            "taskId": task_id,
            "amount": 20,
            "createdAt": "2025-01-01T11:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    // Now test GET /api/v1/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check habits
    let habits = json.get("habits").unwrap().as_array().unwrap();
    assert_eq!(habits.len(), 1);
    assert_eq!(habits[0].get("id").unwrap(), habit_id);
    assert_eq!(habits[0].get("name").unwrap(), "Test Habit");

    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 2);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("dueDate").unwrap(), "2025-01-02T09:00:00");
    assert_eq!(tasks[1].get("id").unwrap(), &dependent_task_id);

    // Check trades
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 2);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("habitId").unwrap(), habit_id);
    assert_eq!(trades[0].get("amount").unwrap(), 500);
    assert_eq!(trades[1].get("id").unwrap(), &task_trade_id);
    assert_eq!(trades[1].get("taskId").unwrap(), &task_id);
    assert_eq!(trades[1].get("amount").unwrap(), 20);

    let task_tags = json.get("taskTags").unwrap().as_array().unwrap();
    assert_eq!(task_tags.len(), 1);
    assert_eq!(task_tags[0].get("taskId").unwrap(), &task_id);
    assert_eq!(task_tags[0].get("tagId").unwrap(), &tag_id);

    let task_task_dependencies = json
        .get("taskTaskDependencies")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(task_task_dependencies.len(), 1);
    assert_eq!(
        task_task_dependencies[0].get("taskId").unwrap(),
        &dependent_task_id
    );
    assert_eq!(
        task_task_dependencies[0].get("dependsOnTaskId").unwrap(),
        &task_id
    );

    let task_habit_dependencies = json
        .get("taskHabitDependencies")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(task_habit_dependencies.len(), 1);
    assert_eq!(
        task_habit_dependencies[0].get("taskId").unwrap(),
        &dependent_task_id
    );
    assert_eq!(task_habit_dependencies[0].get("habitId").unwrap(), habit_id);
    assert_eq!(
        task_habit_dependencies[0]
            .get("requiredCompletions")
            .unwrap(),
        2
    );
    assert_eq!(
        task_habit_dependencies[0]
            .get("baselineCompletionCount")
            .unwrap(),
        1
    );

    // Check balance
    let balance = json.get("balance").unwrap();
    assert_eq!(balance.get("tofuBalance").unwrap(), 520.0);

    // Check sync cursor and serverTime
    assert!(json.get("serverCursor").is_some());
    assert!(json.get("serverCursor").unwrap().is_string());
    assert!(json.get("serverTime").is_some());
    assert!(json.get("serverTime").unwrap().is_string());

    // Check user data
    assert_eq!(json.get("email").unwrap(), &email);
    assert_eq!(json.get("isPremium").unwrap(), false);
    assert_eq!(json.get("generalDifficulty").unwrap(), 5.0);
}

#[tokio::test]
async fn test_sync_pull_generates_stable_special_offers_for_same_window() {
    let email =
        generate_email_from_fn!(test_sync_pull_generates_stable_special_offers_for_same_window);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tasks: Vec<Value> = (0..4)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Task {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T09:0{index}:00"),
                "updatedAt": format!("2025-01-01T09:0{index}:00")
            })
        })
        .collect();

    let habits: Vec<Value> = (0..3)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Habit {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T10:0{index}:00"),
                "updatedAt": format!("2025-01-01T10:0{index}:00")
            })
        })
        .collect();

    let rewards: Vec<Value> = (0..3)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Reward {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T11:0{index}:00"),
                "updatedAt": format!("2025-01-01T11:0{index}:00")
            })
        })
        .collect();

    let sync_body = json!({
        "tasks": tasks,
        "habits": habits,
        "rewards": rewards
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    let (_, first_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let (_, second_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    let first_offers = first_pull.get("specialOffers").unwrap().as_array().unwrap();
    let second_offers = second_pull
        .get("specialOffers")
        .unwrap()
        .as_array()
        .unwrap();

    assert_eq!(first_offers.len(), 1);
    assert_eq!(first_offers, second_offers);

    let offer = &first_offers[0];
    let entity_kind = offer.get("entityKind").unwrap().as_str().unwrap();
    let modifier_percent = offer.get("modifierPercent").unwrap().as_i64().unwrap();

    assert!(matches!(entity_kind, "task" | "habit" | "reward"));
    assert!(matches!(modifier_percent.abs(), 30 | 40 | 50));

    match entity_kind {
        "task" | "habit" => assert!(modifier_percent > 0),
        "reward" => assert!(modifier_percent < 0),
        _ => unreachable!(),
    }
}

#[tokio::test]
async fn test_sync_pull_caps_special_offers_at_five() {
    let email = generate_email_from_fn!(test_sync_pull_caps_special_offers_at_five);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tasks: Vec<Value> = (0..55)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Task {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T09:{:02}:00", index % 60),
                "updatedAt": format!("2025-01-01T09:{:02}:00", index % 60)
            })
        })
        .collect();

    make_authenticated_post_request(&access_token, "/api/v1/sync", json!({ "tasks": tasks })).await;

    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let offers = pull_json.get("specialOffers").unwrap().as_array().unwrap();

    assert_eq!(offers.len(), 5);
}

#[tokio::test]
async fn test_sync_pull_replaces_special_offer_for_completed_task() {
    let email = generate_email_from_fn!(test_sync_pull_replaces_special_offer_for_completed_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tasks: Vec<Value> = (0..21)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Task {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T09:{:02}:00", index % 60),
                "updatedAt": format!("2025-01-01T09:{:02}:00", index % 60)
            })
        })
        .collect();

    make_authenticated_post_request(&access_token, "/api/v1/sync", json!({ "tasks": tasks })).await;

    let (_, initial_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let initial_offers = initial_pull
        .get("specialOffers")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(initial_offers.len(), 2);

    let offered_task_id = initial_offers[0]
        .get("entityId")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();
    let offered_task = tasks
        .iter()
        .find(|task| task.get("id").unwrap().as_str().unwrap() == offered_task_id)
        .unwrap();
    let trade_id = uuid::Uuid::new_v4().to_string();

    make_authenticated_post_request(
        &access_token,
        "/api/v1/sync",
        json!({
            "tasks": [{
                "id": offered_task_id,
                "name": offered_task.get("name").unwrap().as_str().unwrap(),
                "description": offered_task.get("description").unwrap().as_str().unwrap(),
                "createdAt": offered_task.get("createdAt").unwrap().as_str().unwrap(),
                "updatedAt": "2025-01-01T12:00:00",
                "completedAt": "2025-01-01T12:00:00"
            }],
            "trades": [{
                "id": trade_id,
                "taskId": initial_offers[0].get("entityId").unwrap().as_str().unwrap(),
                "amount": 20,
                "createdAt": "2025-01-01T12:00:00"
            }]
        }),
    )
    .await;

    let (_, refreshed_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let refreshed_offers = refreshed_pull
        .get("specialOffers")
        .unwrap()
        .as_array()
        .unwrap();
    let active_refreshed_offers: Vec<&Value> = refreshed_offers
        .iter()
        .filter(|offer| offer.get("deletedAt").unwrap().is_null())
        .collect();

    assert_eq!(active_refreshed_offers.len(), 2);
    assert!(!active_refreshed_offers
        .iter()
        .any(|offer| { offer.get("entityId").unwrap().as_str().unwrap() == offered_task_id }));
}

#[tokio::test]
async fn test_sync_pull_replaces_special_offer_for_deleted_reward() {
    let email = generate_email_from_fn!(test_sync_pull_replaces_special_offer_for_deleted_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let rewards: Vec<Value> = (0..21)
        .map(|index| {
            json!({
                "id": uuid::Uuid::new_v4().to_string(),
                "name": format!("Reward {index}"),
                "description": "",
                "createdAt": format!("2025-01-01T11:{:02}:00", index % 60),
                "updatedAt": format!("2025-01-01T11:{:02}:00", index % 60)
            })
        })
        .collect();

    make_authenticated_post_request(&access_token, "/api/v1/sync", json!({ "rewards": rewards }))
        .await;

    let (_, initial_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let initial_offers = initial_pull
        .get("specialOffers")
        .unwrap()
        .as_array()
        .unwrap();
    assert_eq!(initial_offers.len(), 2);

    let offered_reward_id = initial_offers[0]
        .get("entityId")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();
    let offered_reward = rewards
        .iter()
        .find(|reward| reward.get("id").unwrap().as_str().unwrap() == offered_reward_id)
        .unwrap();

    make_authenticated_post_request(
        &access_token,
        "/api/v1/sync",
        json!({
            "rewards": [{
                "id": offered_reward_id,
                "name": offered_reward.get("name").unwrap().as_str().unwrap(),
                "description": offered_reward.get("description").unwrap().as_str().unwrap(),
                "createdAt": offered_reward.get("createdAt").unwrap().as_str().unwrap(),
                "updatedAt": "2025-01-01T12:30:00",
                "deletedAt": "2025-01-01T12:30:00"
            }]
        }),
    )
    .await;

    let (_, refreshed_pull) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let refreshed_offers = refreshed_pull
        .get("specialOffers")
        .unwrap()
        .as_array()
        .unwrap();
    let active_refreshed_offers: Vec<&Value> = refreshed_offers
        .iter()
        .filter(|offer| offer.get("deletedAt").unwrap().is_null())
        .collect();

    assert_eq!(active_refreshed_offers.len(), 2);
    assert!(!active_refreshed_offers
        .iter()
        .any(|offer| { offer.get("entityId").unwrap().as_str().unwrap() == offered_reward_id }));
}

#[tokio::test]
async fn test_sync_pull_with_since_filters_all_entities() {
    let email = generate_email_from_fn!(test_sync_pull_with_since_filters_all_entities);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create first habit
    let habit_body = json!({
        "name": "Old Habit",
        "description": "Created before timestamp"
    });
    make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;

    // Get current sync cursor
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let server_cursor = pull_json
        .get("serverCursor")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Create a new habit after getting the timestamp
    let habit_body_2 = json!({
        "name": "New Habit",
        "description": "Created after timestamp"
    });
    let (_, new_habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body_2).await;
    let new_habit_id = new_habit_json.get("id").unwrap().as_str().unwrap();

    // Pull since the cursor - should only get the new habit
    let url = format!(
        "/api/v1/sync?cursor={}",
        urlencoding::encode(&server_cursor)
    );
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;

    assert_eq!(status, StatusCode::OK);

    let habits = json.get("habits").unwrap().as_array().unwrap();
    assert_eq!(habits.len(), 1);
    assert_eq!(habits[0].get("id").unwrap(), new_habit_id);
    assert_eq!(habits[0].get("name").unwrap(), "New Habit");

    // No new trades since timestamp
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 0);
}

#[tokio::test]
async fn test_sync_pull_balance_sums_only_active_trade_history() {
    let email = generate_email_from_fn!(test_sync_pull_balance_sums_only_active_trade_history);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_body = json!({
        "name": "Balance Source Habit",
        "description": "Trade history should be authoritative"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap();

    let sync_body = json!({
        "trades": [
            {
                "id": uuid::Uuid::new_v4().to_string(),
                "habitId": habit_id,
                "amount": 282,
                "createdAt": "2025-01-01T10:00:00"
            },
            {
                "id": uuid::Uuid::new_v4().to_string(),
                "habitId": habit_id,
                "amount": 50,
                "createdAt": "2025-01-01T10:05:00",
                "deletedAt": "2025-01-01T10:10:00"
            }
        ]
    });
    let (push_status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;
    assert_eq!(push_status, StatusCode::OK);
    assert_eq!(
        push_json
            .get("balance")
            .unwrap()
            .get("tofuBalance")
            .unwrap(),
        282.0
    );

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(pull_status, StatusCode::OK);
    assert_eq!(
        pull_json.get("trades").unwrap().as_array().unwrap().len(),
        2
    );
    assert_eq!(
        pull_json
            .get("balance")
            .unwrap()
            .get("tofuBalance")
            .unwrap(),
        282.0
    );
}

#[tokio::test]
async fn test_sync_pull_empty_for_new_user() {
    let email = generate_email_from_fn!(test_sync_pull_empty_for_new_user);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("tasks").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("habits").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("taskTags").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(
        json.get("taskTaskDependencies")
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        0
    );
    assert_eq!(
        json.get("taskHabitDependencies")
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        0
    );
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        0.0
    );
    assert!(json.get("serverTime").unwrap().is_string());

    // User data should still be present
    assert_eq!(json.get("email").unwrap(), &email);
    assert_eq!(json.get("isPremium").unwrap(), false);
}

#[tokio::test]
async fn test_sync_pull_requires_authentication() {
    let (status, _) = make_unauthenticated_get_request("/api/v1/sync").await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

// ============================================================================
// Sync Push (POST /api/v1/sync) Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_habit_and_trade_atomically() {
    let email = generate_email_from_fn!(test_sync_push_creates_habit_and_trade_atomically);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "New Habit",
            "description": "Created atomically",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    // Check habit was created
    let habits = json.get("habits").unwrap().as_array().unwrap();
    assert_eq!(habits.len(), 1);
    assert_eq!(habits[0].get("id").unwrap(), &habit_id);
    assert_eq!(habits[0].get("name").unwrap(), "New Habit");

    // Check trade was created
    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("habitId").unwrap(), &habit_id);
    assert_eq!(trades[0].get("amount").unwrap(), 500);

    // Check balance updated
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        500.0
    );
}

#[tokio::test]
async fn test_sync_push_and_pull_round_trip_refund_trades() {
    let email = generate_email_from_fn!(test_sync_push_and_pull_round_trip_refund_trades);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_body = json!({
        "name": "Refundable Habit",
        "description": "Refund trades should sync"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap().to_string();

    let active_trade_id = uuid::Uuid::new_v4().to_string();
    let refunded_trade_id = uuid::Uuid::new_v4().to_string();
    let push_body = json!({
        "trades": [{
            "id": active_trade_id,
            "habitId": habit_id,
            "sourceName": "Refundable Habit",
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }, {
            "id": refunded_trade_id,
            "habitId": habit_id,
            "sourceName": "Refundable Habit refund",
            "amount": -500,
            "createdAt": "2025-01-01T10:10:00",
            "refundsTradeId": active_trade_id
        }]
    });

    let (push_status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", push_body).await;

    assert_eq!(push_status, StatusCode::OK);

    let pushed_trades = push_json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(pushed_trades.len(), 2);
    let pushed_active_trade = pushed_trades
        .iter()
        .find(|trade| trade.get("id").unwrap() == &active_trade_id)
        .unwrap();
    let pushed_refunded_trade = pushed_trades
        .iter()
        .find(|trade| trade.get("id").unwrap() == &refunded_trade_id)
        .unwrap();
    assert_eq!(
        pushed_active_trade.get("refundsTradeId").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        pushed_active_trade.get("sourceName").unwrap(),
        "Refundable Habit"
    );
    assert_eq!(
        pushed_refunded_trade.get("refundsTradeId").unwrap(),
        &active_trade_id
    );
    assert_eq!(
        pushed_refunded_trade.get("sourceName").unwrap(),
        "Refundable Habit refund"
    );
    assert_eq!(
        push_json
            .get("balance")
            .unwrap()
            .get("tofuBalance")
            .unwrap(),
        0.0
    );

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(pull_status, StatusCode::OK);

    let pulled_trades = pull_json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(pulled_trades.len(), 2);
    let pulled_active_trade = pulled_trades
        .iter()
        .find(|trade| trade.get("id").unwrap() == &active_trade_id)
        .unwrap();
    let pulled_refunded_trade = pulled_trades
        .iter()
        .find(|trade| trade.get("id").unwrap() == &refunded_trade_id)
        .unwrap();
    assert_eq!(
        pulled_active_trade.get("refundsTradeId").unwrap(),
        &serde_json::Value::Null
    );
    assert_eq!(
        pulled_active_trade.get("sourceName").unwrap(),
        "Refundable Habit"
    );
    assert_eq!(
        pulled_refunded_trade.get("refundsTradeId").unwrap(),
        &active_trade_id
    );
    assert_eq!(
        pulled_refunded_trade.get("sourceName").unwrap(),
        "Refundable Habit refund"
    );
    assert_eq!(
        pull_json
            .get("balance")
            .unwrap()
            .get("tofuBalance")
            .unwrap(),
        0.0
    );
}

#[tokio::test]
async fn test_sync_push_rejects_completed_task_when_habit_dependency_trade_is_refunded() {
    let email = generate_email_from_fn!(
        test_sync_push_rejects_completed_task_when_habit_dependency_trade_is_refunded
    );
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_body = json!({
        "name": "Dependency Habit",
        "description": "Refunded completions should not satisfy task dependencies"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap().to_string();

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let refund_trade_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Ship build",
            "description": "Blocked until the habit dependency is active",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "completedAt": "2025-01-01T10:10:00"
        }],
        "taskHabitDependencies": [{
            "taskId": task_id,
            "habitId": habit_id,
            "requiredCompletions": 1,
            "baselineCompletionCount": 0,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "sourceName": "Dependency Habit",
            "amount": 100,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T10:05:00"
        }, {
            "id": refund_trade_id,
            "habitId": habit_id,
            "sourceName": "Dependency Habit refund",
            "amount": -100,
            "createdAt": "2025-01-01T10:06:00",
            "refundsTradeId": trade_id
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        json["errors"][0]["message"],
        "Validation Error: Task dependencies must be complete before this task can be completed."
    );

    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert!(pull_json
        .get("tasks")
        .unwrap()
        .as_array()
        .unwrap()
        .iter()
        .all(|task| task.get("id").unwrap() != &task_id));
}

#[tokio::test]
async fn test_sync_push_refund_trade_reopens_task_without_task_row_update() {
    let email =
        generate_email_from_fn!(test_sync_push_refund_trade_reopens_task_without_task_row_update);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let refund_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Submit report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "completedAt": "2025-01-01T09:30:00"
        }],
        "trades": [{
            "id": trade_id,
            "taskId": task_id,
            "sourceName": "Submit report",
            "amount": 120,
            "createdAt": "2025-01-01T09:30:00"
        }]
    });
    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let refund_body = json!({
        "trades": [{
            "id": refund_trade_id,
            "taskId": task_id,
            "sourceName": "Submit report refund",
            "amount": -120,
            "createdAt": "2025-01-01T09:35:00",
            "refundsTradeId": trade_id
        }]
    });
    let (refund_status, refund_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", refund_body).await;

    assert_eq!(refund_status, StatusCode::OK);
    assert_eq!(refund_json["balance"]["tofuBalance"], 0.0);

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_status, StatusCode::OK);

    let task = pull_json["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .find(|task| task["id"] == task_id)
        .unwrap();
    assert_eq!(task.get("completedAt").unwrap(), &Value::Null);
}

#[tokio::test]
async fn test_sync_push_refunded_prerequisite_task_no_longer_satisfies_dependencies() {
    let email = generate_email_from_fn!(
        test_sync_push_refunded_prerequisite_task_no_longer_satisfies_dependencies
    );
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let prerequisite_task_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_id = uuid::Uuid::new_v4().to_string();
    let prerequisite_trade_id = uuid::Uuid::new_v4().to_string();
    let refund_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "tasks": [{
            "id": prerequisite_task_id,
            "name": "Draft report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "completedAt": "2025-01-01T09:30:00"
        }, {
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "taskTaskDependencies": [{
            "taskId": blocked_task_id,
            "dependsOnTaskId": prerequisite_task_id,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T10:05:00"
        }],
        "trades": [{
            "id": prerequisite_trade_id,
            "taskId": prerequisite_task_id,
            "sourceName": "Draft report",
            "amount": 80,
            "createdAt": "2025-01-01T09:30:00"
        }]
    });
    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let refund_body = json!({
        "trades": [{
            "id": refund_trade_id,
            "taskId": prerequisite_task_id,
            "sourceName": "Draft report refund",
            "amount": -80,
            "createdAt": "2025-01-01T09:35:00",
            "refundsTradeId": prerequisite_trade_id
        }]
    });
    let (refund_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", refund_body).await;
    assert_eq!(refund_status, StatusCode::OK);

    let complete_body = json!({
        "tasks": [{
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "completedAt": "2025-01-01T11:00:00"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", complete_body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        json["errors"][0]["message"],
        "Validation Error: Task dependencies must be complete before this task can be completed."
    );
}

#[tokio::test]
async fn test_sync_push_rejects_refund_trade_before_original_trade_time() {
    let email =
        generate_email_from_fn!(test_sync_push_rejects_refund_trade_before_original_trade_time);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_body = json!({
        "name": "Refundable Habit",
        "description": "Refund trades should follow the original event"
    });
    let (_, habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/habits", habit_body).await;
    let habit_id = habit_json.get("id").unwrap().as_str().unwrap().to_string();

    let trade_id = uuid::Uuid::new_v4().to_string();
    let setup_body = json!({
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "sourceName": "Refundable Habit",
            "amount": 100,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });
    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let refund_body = json!({
        "trades": [{
            "id": uuid::Uuid::new_v4().to_string(),
            "habitId": habit_id,
            "sourceName": "Refundable Habit refund",
            "amount": -100,
            "createdAt": "2025-01-01T09:59:59",
            "refundsTradeId": trade_id
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", refund_body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        json["errors"][0]["message"],
        "Validation Error: Refund trades cannot be created before the original trade."
    );
}

#[tokio::test]
async fn test_sync_push_allows_task_completion_after_dependency_is_removed() {
    let email =
        generate_email_from_fn!(test_sync_push_allows_task_completion_after_dependency_is_removed);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let dependency_task_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "tasks": [{
            "id": dependency_task_id,
            "name": "Draft report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00"
        }, {
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "taskTaskDependencies": [{
            "taskId": blocked_task_id,
            "dependsOnTaskId": dependency_task_id,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T10:05:00"
        }]
    });

    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let completion_body = json!({
        "tasks": [{
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "completedAt": "2025-01-01T11:00:00"
        }],
        "trades": [{
            "id": blocked_task_trade_id,
            "taskId": blocked_task_id,
            "amount": 1000,
            "createdAt": "2025-01-01T11:00:00"
        }],
        "taskTaskDependencies": [{
            "taskId": blocked_task_id,
            "dependsOnTaskId": dependency_task_id,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": "2025-01-01T11:00:00"
        }]
    });

    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", completion_body).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["tasks"].as_array().unwrap()[0]
            .get("completedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:00"
    );
}

#[tokio::test]
async fn test_sync_push_creates_task_task_tag_and_trade_atomically() {
    let email = generate_email_from_fn!(test_sync_push_creates_task_task_tag_and_trade_atomically);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Renew passport",
            "description": "Book the appointment",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "difficultyTier": "medium",
            "durationSeconds": 1200,
            "commitment": 3,
            "dueDate": "2025-02-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Admin",
            "colorHex": "#445566",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "taskTags": [{
            "taskId": task_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "taskId": task_id,
            "amount": 151,
            "createdAt": "2025-01-01T11:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    let tasks = json.get("tasks").unwrap().as_array().unwrap();
    assert_eq!(tasks.len(), 1);
    assert_eq!(tasks[0].get("id").unwrap(), &task_id);
    assert_eq!(tasks[0].get("completedAt").unwrap(), "2025-01-01T11:00:00");

    let task_tags = json.get("taskTags").unwrap().as_array().unwrap();
    assert_eq!(task_tags.len(), 1);
    assert_eq!(task_tags[0].get("taskId").unwrap(), &task_id);
    assert_eq!(task_tags[0].get("tagId").unwrap(), &tag_id);

    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("taskId").unwrap(), &task_id);

    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        151.0
    );
}

#[tokio::test]
async fn test_sync_push_task_rejects_legacy_skip_consequence_field() {
    let email = generate_email_from_fn!(test_sync_push_task_rejects_legacy_skip_consequence_field);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Legacy task",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "skipConsequence": 4
        }]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_sync_push_task_rejects_unknown_habit_benefit_field() {
    let email = generate_email_from_fn!(test_sync_push_task_rejects_unknown_habit_benefit_field);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Bad task",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "benefit": 4
        }]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_sync_push_updates_existing_task_due_date() {
    let email = generate_email_from_fn!(test_sync_push_updates_existing_task_due_date);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_id = uuid::Uuid::new_v4().to_string();

    let initial_body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Renew passport",
            "description": "Book the appointment",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "difficultyTier": "medium",
            "durationSeconds": 1200,
            "commitment": 3
        }]
    });

    let (initial_status, initial_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", initial_body).await;
    assert_eq!(initial_status, StatusCode::OK);
    assert_eq!(
        initial_json.get("tasks").unwrap().as_array().unwrap()[0]
            .get("dueDate")
            .unwrap(),
        &Value::Null
    );

    let update_body = json!({
        "tasks": [{
            "id": task_id,
            "name": "Renew passport",
            "description": "Book the appointment",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-02T10:00:00",
            "difficultyTier": "medium",
            "durationSeconds": 1200,
            "commitment": 3,
            "dueDate": "2025-02-01T10:00:00"
        }]
    });

    let (update_status, update_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", update_body).await;

    assert_eq!(update_status, StatusCode::OK);
    assert_eq!(
        update_json.get("tasks").unwrap().as_array().unwrap()[0]
            .get("dueDate")
            .unwrap(),
        "2025-02-01T10:00:00"
    );

    let (pull_status, pull_json) =
        make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_status, StatusCode::OK);
    assert_eq!(
        pull_json.get("tasks").unwrap().as_array().unwrap()[0]
            .get("dueDate")
            .unwrap(),
        "2025-02-01T10:00:00"
    );
}

#[tokio::test]
async fn test_sync_push_rejects_task_completion_until_dependencies_are_satisfied() {
    let email = generate_email_from_fn!(
        test_sync_push_rejects_task_completion_until_dependencies_are_satisfied
    );
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let dependency_task_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_id = uuid::Uuid::new_v4().to_string();
    let habit_blocked_task_id = uuid::Uuid::new_v4().to_string();
    let habit_id = uuid::Uuid::new_v4().to_string();
    let habit_trade_id = uuid::Uuid::new_v4().to_string();
    let dependency_task_trade_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "tasks": [{
            "id": dependency_task_id,
            "name": "Draft report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00",
            "completedAt": "2025-01-01T09:30:00"
        }, {
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }, {
            "id": habit_blocked_task_id,
            "name": "Share checklist",
            "description": "",
            "createdAt": "2025-01-01T10:01:00",
            "updatedAt": "2025-01-01T10:01:00"
        }],
        "habits": [{
            "id": habit_id,
            "name": "Proofread",
            "description": "",
            "createdAt": "2025-01-01T08:00:00",
            "updatedAt": "2025-01-01T08:00:00"
        }],
        "trades": [{
            "id": habit_trade_id,
            "habitId": habit_id,
            "amount": 1000,
            "createdAt": "2025-01-01T08:30:00"
        }, {
            "id": dependency_task_trade_id,
            "taskId": dependency_task_id,
            "amount": 1000,
            "createdAt": "2025-01-01T09:30:00"
        }],
        "taskTaskDependencies": [{
            "taskId": blocked_task_id,
            "dependsOnTaskId": dependency_task_id,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T10:05:00"
        }],
        "taskHabitDependencies": [{
            "taskId": blocked_task_id,
            "habitId": habit_id,
            "requiredCompletions": 2,
            "baselineCompletionCount": 1,
            "createdAt": "2025-01-01T10:06:00",
            "updatedAt": "2025-01-01T10:06:00"
        }]
    });

    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let blocked_completion_body = json!({
        "tasks": [{
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "completedAt": "2025-01-01T11:00:00"
        }],
        "trades": [{
            "id": blocked_task_trade_id,
            "taskId": blocked_task_id,
            "amount": 1000,
            "createdAt": "2025-01-01T11:00:00"
        }]
    });

    let (blocked_status, blocked_json) = make_authenticated_post_request(
        &access_token,
        "/api/v1/sync",
        blocked_completion_body.clone(),
    )
    .await;
    assert_eq!(blocked_status, StatusCode::BAD_REQUEST);
    assert_eq!(
        blocked_json["errors"][0]["message"],
        "Validation Error: Task dependencies must be complete before this task can be completed."
    );

    let second_habit_trade_id = uuid::Uuid::new_v4().to_string();
    let third_habit_trade_id = uuid::Uuid::new_v4().to_string();
    let satisfy_habit_body = json!({
        "trades": [{
            "id": second_habit_trade_id,
            "habitId": habit_id,
            "amount": 1000,
            "createdAt": "2025-01-01T10:30:00"
        }, {
            "id": third_habit_trade_id,
            "habitId": habit_id,
            "amount": 1000,
            "createdAt": "2025-01-01T10:40:00"
        }]
    });
    let (habit_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", satisfy_habit_body).await;
    assert_eq!(habit_status, StatusCode::OK);

    let (completion_status, completion_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", blocked_completion_body)
            .await;
    assert_eq!(completion_status, StatusCode::OK);
    assert_eq!(
        completion_json["tasks"].as_array().unwrap()[0]
            .get("completedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:00"
    );
}

#[tokio::test]
async fn test_sync_push_rejects_dependency_cycles() {
    let email = generate_email_from_fn!(test_sync_push_rejects_dependency_cycles);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let task_a_id = uuid::Uuid::new_v4().to_string();
    let task_b_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "tasks": [{
            "id": task_a_id,
            "name": "Task A",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00"
        }, {
            "id": task_b_id,
            "name": "Task B",
            "description": "",
            "createdAt": "2025-01-01T09:10:00",
            "updatedAt": "2025-01-01T09:10:00"
        }],
        "taskTaskDependencies": [{
            "taskId": task_a_id,
            "dependsOnTaskId": task_b_id,
            "createdAt": "2025-01-01T09:15:00",
            "updatedAt": "2025-01-01T09:15:00"
        }, {
            "taskId": task_b_id,
            "dependsOnTaskId": task_a_id,
            "createdAt": "2025-01-01T09:16:00",
            "updatedAt": "2025-01-01T09:16:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(
        json["errors"][0]["message"],
        "Validation Error: Task dependencies cannot contain cycles."
    );
}

#[tokio::test]
async fn test_sync_push_deleting_task_soft_deletes_links_to_that_task() {
    let email =
        generate_email_from_fn!(test_sync_push_deleting_task_soft_deletes_links_to_that_task);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let dependency_task_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_id = uuid::Uuid::new_v4().to_string();
    let habit_blocked_task_id = uuid::Uuid::new_v4().to_string();
    let habit_id = uuid::Uuid::new_v4().to_string();
    let blocked_task_trade_id = uuid::Uuid::new_v4().to_string();

    let setup_body = json!({
        "tasks": [{
            "id": dependency_task_id,
            "name": "Draft report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T09:00:00"
        }, {
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }, {
            "id": habit_blocked_task_id,
            "name": "Share checklist",
            "description": "",
            "createdAt": "2025-01-01T10:01:00",
            "updatedAt": "2025-01-01T10:01:00"
        }],
        "habits": [{
            "id": habit_id,
            "name": "Proofread",
            "description": "",
            "createdAt": "2025-01-01T08:00:00",
            "updatedAt": "2025-01-01T08:00:00"
        }],
        "taskTaskDependencies": [{
            "taskId": blocked_task_id,
            "dependsOnTaskId": dependency_task_id,
            "createdAt": "2025-01-01T10:05:00",
            "updatedAt": "2025-01-01T10:05:00"
        }],
        "taskHabitDependencies": [{
            "taskId": dependency_task_id,
            "habitId": habit_id,
            "requiredCompletions": 1,
            "baselineCompletionCount": 0,
            "createdAt": "2025-01-01T10:06:00",
            "updatedAt": "2025-01-01T10:06:00"
        }, {
            "taskId": habit_blocked_task_id,
            "habitId": habit_id,
            "requiredCompletions": 1,
            "baselineCompletionCount": 0,
            "createdAt": "2025-01-01T10:07:00",
            "updatedAt": "2025-01-01T10:07:00"
        }]
    });

    let (setup_status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", setup_body).await;
    assert_eq!(setup_status, StatusCode::OK);

    let delete_task_body = json!({
        "tasks": [{
            "id": dependency_task_id,
            "name": "Draft report",
            "description": "",
            "createdAt": "2025-01-01T09:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": "2025-01-01T11:00:00"
        }]
    });

    let (delete_task_status, delete_task_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", delete_task_body).await;
    assert_eq!(delete_task_status, StatusCode::OK);
    assert_eq!(
        delete_task_json["tasks"].as_array().unwrap()[0]
            .get("deletedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:00"
    );
    assert_eq!(
        delete_task_json["taskTaskDependencies"].as_array().unwrap()[0]
            .get("deletedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:00"
    );
    assert_eq!(
        delete_task_json["taskHabitDependencies"]
            .as_array()
            .unwrap()[0]
            .get("deletedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:00"
    );

    let complete_blocked_task_body = json!({
        "tasks": [{
            "id": blocked_task_id,
            "name": "Send report",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:30",
            "completedAt": "2025-01-01T11:00:30"
        }],
        "trades": [{
            "id": blocked_task_trade_id,
            "taskId": blocked_task_id,
            "amount": 1000,
            "createdAt": "2025-01-01T11:00:30"
        }]
    });
    let (complete_blocked_task_status, complete_blocked_task_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", complete_blocked_task_body)
            .await;
    assert_eq!(complete_blocked_task_status, StatusCode::OK);
    assert_eq!(
        complete_blocked_task_json["tasks"].as_array().unwrap()[0]
            .get("completedAt")
            .unwrap()
            .as_str()
            .unwrap(),
        "2025-01-01T11:00:30"
    );

    let delete_habit_body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Proofread",
            "description": "",
            "createdAt": "2025-01-01T08:00:00",
            "updatedAt": "2025-01-01T11:05:00",
            "deletedAt": "2025-01-01T11:05:00"
        }]
    });

    let (delete_habit_status, delete_habit_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", delete_habit_body).await;
    assert_eq!(delete_habit_status, StatusCode::BAD_REQUEST);
    assert_eq!(
        delete_habit_json["errors"][0]["message"],
        "Validation Error: This item cannot be deleted while active tasks still depend on it."
    );
}

#[tokio::test]
async fn test_sync_push_ordering_habit_before_trade() {
    let email = generate_email_from_fn!(test_sync_push_ordering_habit_before_trade);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // Send trade that references a habit that will be created in the same request
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Habit Created First",
            "description": "Even though trade references it",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 300,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(
        json.get("errors").is_none(),
        "Should not have errors: {:?}",
        json
    );

    assert_eq!(json.get("habits").unwrap().as_array().unwrap().len(), 1);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 1);
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        300.0
    );
}

#[tokio::test]
async fn test_sync_push_partial_failure_rolls_back() {
    let email = generate_email_from_fn!(test_sync_push_partial_failure_rolls_back);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_habit_id = uuid::Uuid::new_v4().to_string();

    // Try to create a habit and a trade that references a non-existent habit
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "This Should Not Be Saved",
            "description": "Because trade will fail",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": non_existent_habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    // Should have an error
    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error status, got: {} with body: {:?}",
        status,
        json
    );

    // Now verify the habit was NOT saved by pulling
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let habits = pull_json.get("habits").unwrap().as_array().unwrap();
    assert_eq!(
        habits.len(),
        0,
        "Habit should not have been saved due to rollback"
    );
}

#[tokio::test]
async fn test_sync_push_empty_input_succeeds() {
    let email = generate_email_from_fn!(test_sync_push_empty_input_succeeds);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Push with empty input
    let body = json!({});

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(
        json.get("errors").is_none(),
        "Should not have errors: {:?}",
        json
    );

    assert_eq!(json.get("habits").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert!(json.get("serverTime").unwrap().is_string());
}

#[tokio::test]
async fn test_sync_push_updates_balance_correctly() {
    let email = generate_email_from_fn!(test_sync_push_updates_balance_correctly);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade1_id = uuid::Uuid::new_v4().to_string();
    let trade2_id = uuid::Uuid::new_v4().to_string();

    // Create habit and two trades in one sync
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Habit",
            "description": "For balance test",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [
            {
                "id": trade1_id,
                "habitId": habit_id,
                "amount": 500,
                "createdAt": "2025-01-01T10:00:00"
            },
            {
                "id": trade2_id,
                "habitId": habit_id,
                "amount": 300,
                "createdAt": "2025-01-01T10:01:00"
            }
        ]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none(), "Response: {:?}", json);

    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 2);
    // Balance should be sum of both trades: 500 + 300 = 800
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        800.0
    );
}

#[tokio::test]
async fn test_sync_push_requires_authentication() {
    let body = json!({
        "habits": [{
            "id": uuid::Uuid::new_v4().to_string(),
            "name": "Test",
            "description": "Test",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, _) = make_unauthenticated_post_request("/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn test_sync_push_trade_invalid_habit_reference_fails() {
    let email = generate_email_from_fn!(test_sync_push_trade_invalid_habit_reference_fails);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_habit_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "trades": [{
            "id": trade_id,
            "habitId": non_existent_habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Should have error for invalid habit reference"
    );
    assert!(
        json.get("errors").is_some(),
        "Should have errors for invalid habit reference"
    );
}

#[tokio::test]
async fn test_sync_push_validates_habit_fields() {
    let email = generate_email_from_fn!(test_sync_push_validates_habit_fields);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    // Name too long (>100 chars)
    let long_name = "a".repeat(101);

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": long_name,
            "description": "Valid description",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(
        json.get("errors").is_some(),
        "Should have validation error for long name"
    );

    let errors = json.get("errors").unwrap().as_array().unwrap();
    let error = &errors[0];
    assert_eq!(
        error.get("code").unwrap().as_str().unwrap(),
        "BAD_USER_INPUT"
    );
}

#[tokio::test]
async fn test_sync_push_idempotent_same_ids() {
    let email = generate_email_from_fn!(test_sync_push_idempotent_same_ids);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Original Name",
            "description": "Original",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    // First push
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        500.0
    );

    // Push same data again - should be idempotent
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());
    // Balance should still be 500 (not 1000)
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        500.0
    );

    // Verify only one habit and one trade exist
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(
        pull_json.get("habits").unwrap().as_array().unwrap().len(),
        1
    );
    assert_eq!(
        pull_json.get("trades").unwrap().as_array().unwrap().len(),
        1
    );
}

// ============================================================================
// Roundtrip and Incremental Sync Tests
// ============================================================================

#[tokio::test]
async fn test_unified_sync_roundtrip_push_then_pull() {
    let email = generate_email_from_fn!(test_unified_sync_roundtrip_push_then_pull);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    // Push
    let push_body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Roundtrip Habit",
            "description": "Testing roundtrip",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 750,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, _) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", push_body).await;
    assert_eq!(status, StatusCode::OK);

    // Pull and verify
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(status, StatusCode::OK);

    let habits = json.get("habits").unwrap().as_array().unwrap();
    assert_eq!(habits.len(), 1);
    assert_eq!(habits[0].get("id").unwrap(), &habit_id);
    assert_eq!(habits[0].get("name").unwrap(), "Roundtrip Habit");
    assert_eq!(habits[0].get("description").unwrap(), "Testing roundtrip");

    let trades = json.get("trades").unwrap().as_array().unwrap();
    assert_eq!(trades.len(), 1);
    assert_eq!(trades[0].get("id").unwrap(), &trade_id);
    assert_eq!(trades[0].get("habitId").unwrap(), &habit_id);
    assert_eq!(trades[0].get("amount").unwrap(), 750);

    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        750.0
    );
}

#[tokio::test]
async fn test_sync_incremental_after_push() {
    let email = generate_email_from_fn!(test_sync_incremental_after_push);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // First push
    let habit1_id = uuid::Uuid::new_v4().to_string();
    let push1_body = json!({
        "habits": [{
            "id": habit1_id,
            "name": "First Habit",
            "description": "Created first",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (_, json1) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", push1_body).await;
    let server_cursor = json1
        .get("serverCursor")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Second push with new habit
    let habit2_id = uuid::Uuid::new_v4().to_string();
    let push2_body = json!({
        "habits": [{
            "id": habit2_id,
            "name": "Second Habit",
            "description": "Created second",
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00"
        }]
    });

    make_authenticated_post_request(&access_token, "/api/v1/sync", push2_body).await;

    // Incremental pull using the server cursor from first push
    let url = format!(
        "/api/v1/sync?cursor={}",
        urlencoding::encode(&server_cursor)
    );
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;
    assert_eq!(status, StatusCode::OK);

    let habits = json.get("habits").unwrap().as_array().unwrap();
    // Should only get the second habit (created after the first cursor)
    assert_eq!(habits.len(), 1);
    assert_eq!(habits[0].get("id").unwrap(), &habit2_id);
    assert_eq!(habits[0].get("name").unwrap(), "Second Habit");
}

// ============================================================================
// Data Isolation Tests
// ============================================================================

#[tokio::test]
async fn test_sync_only_returns_own_data() {
    let email1 = "test_sync_only_returns_own_data_user1_rest@test.com".to_string();
    let email2 = "test_sync_only_returns_own_data_user2_rest@test.com".to_string();
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates data
    let habit_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();

    let push_body = json!({
        "habits": [{
            "id": habit_id,
            "name": "User 1's Habit",
            "description": "Private",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, _) = make_authenticated_post_request(&token1, "/api/v1/sync", push_body).await;
    assert_eq!(status, StatusCode::OK);

    // User 2 tries to pull
    let (status, json) = make_authenticated_get_request(&token2, "/api/v1/sync").await;
    assert_eq!(status, StatusCode::OK);

    // User 2 should see nothing
    assert_eq!(json.get("habits").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(json.get("trades").unwrap().as_array().unwrap().len(), 0);
    assert_eq!(
        json.get("balance").unwrap().get("tofuBalance").unwrap(),
        0.0
    );
}

// ============================================================================
// Tag Sync Pull Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_includes_tags() {
    let email = generate_email_from_fn!(test_sync_pull_includes_tags);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a tag via sync push
    let tag_id = uuid::Uuid::new_v4().to_string();
    let sync_body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Work",
            "colorHex": "#FF5733FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    // Now test GET /api/v1/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check tags
    let tags = json.get("tags").unwrap().as_array().unwrap();
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].get("id").unwrap(), &tag_id);
    assert_eq!(tags[0].get("name").unwrap(), "Work");
    assert_eq!(tags[0].get("colorHex").unwrap(), "#FF5733FF");
}

#[tokio::test]
async fn test_sync_pull_includes_habit_tags() {
    let email = generate_email_from_fn!(test_sync_pull_includes_habit_tags);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create habit, tag, and association via sync push
    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let sync_body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily workout",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Health",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    // Now test GET /api/v1/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check habitTags
    let habit_tags = json.get("habitTags").unwrap().as_array().unwrap();
    assert_eq!(habit_tags.len(), 1);
    assert_eq!(habit_tags[0].get("habitId").unwrap(), &habit_id);
    assert_eq!(habit_tags[0].get("tagId").unwrap(), &tag_id);
}

#[tokio::test]
async fn test_sync_pull_tags_filtered_by_since() {
    let email = generate_email_from_fn!(test_sync_pull_tags_filtered_by_since);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create first tag
    let tag1_id = uuid::Uuid::new_v4().to_string();
    let sync_body1 = json!({
        "tags": [{
            "id": tag1_id,
            "name": "Old Tag",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    let (_, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body1).await;
    let server_cursor = push_json
        .get("serverCursor")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Create second tag after getting timestamp
    let tag2_id = uuid::Uuid::new_v4().to_string();
    let sync_body2 = json!({
        "tags": [{
            "id": tag2_id,
            "name": "New Tag",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body2).await;

    // Pull since cursor - should only get new tag
    let url = format!(
        "/api/v1/sync?cursor={}",
        urlencoding::encode(&server_cursor)
    );
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;

    assert_eq!(status, StatusCode::OK);

    let tags = json.get("tags").unwrap().as_array().unwrap();
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].get("id").unwrap(), &tag2_id);
    assert_eq!(tags[0].get("name").unwrap(), "New Tag");
}

#[tokio::test]
async fn test_sync_pull_habit_tags_filtered_by_since() {
    let email = generate_email_from_fn!(test_sync_pull_habit_tags_filtered_by_since);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create habit and two tags first
    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag1_id = uuid::Uuid::new_v4().to_string();
    let tag2_id = uuid::Uuid::new_v4().to_string();

    let sync_body1 = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [
            {
                "id": tag1_id,
                "name": "Tag1",
                "colorHex": "#FF0000FF",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            },
            {
                "id": tag2_id,
                "name": "Tag2",
                "colorHex": "#00FF00FF",
                "createdAt": "2025-01-01T10:00:00",
                "updatedAt": "2025-01-01T10:00:00"
            }
        ],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag1_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    let (_, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body1).await;
    let server_cursor = push_json
        .get("serverCursor")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Add second habit-tag association after timestamp
    let sync_body2 = json!({
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag2_id,
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body2).await;

    // Pull since cursor - should only get new association
    let url = format!(
        "/api/v1/sync?cursor={}",
        urlencoding::encode(&server_cursor)
    );
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;

    assert_eq!(status, StatusCode::OK);

    let habit_tags = json.get("habitTags").unwrap().as_array().unwrap();
    assert_eq!(habit_tags.len(), 1);
    assert_eq!(habit_tags[0].get("tagId").unwrap(), &tag2_id);
}

// ============================================================================
// Tag Sync Push Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_tag() {
    let email = generate_email_from_fn!(test_sync_push_creates_tag);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Work",
            "colorHex": "#FF5733FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    let tags = json.get("tags").unwrap().as_array().unwrap();
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].get("id").unwrap(), &tag_id);
    assert_eq!(tags[0].get("name").unwrap(), "Work");
    assert_eq!(tags[0].get("colorHex").unwrap(), "#FF5733FF");
}

#[tokio::test]
async fn test_sync_push_updates_tag() {
    let email = generate_email_from_fn!(test_sync_push_updates_tag);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();

    // Create tag
    let body1 = json!({
        "tags": [{
            "id": tag_id,
            "name": "Original",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body1).await;

    // Update tag
    let body2 = json!({
        "tags": [{
            "id": tag_id,
            "name": "Updated",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body2).await;

    assert_eq!(status, StatusCode::OK);

    let tags = json.get("tags").unwrap().as_array().unwrap();
    assert_eq!(tags.len(), 1);
    assert_eq!(tags[0].get("name").unwrap(), "Updated");
    assert_eq!(tags[0].get("colorHex").unwrap(), "#00FF00FF");
}

#[tokio::test]
async fn test_sync_push_soft_deletes_tag() {
    let email = generate_email_from_fn!(test_sync_push_soft_deletes_tag);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();

    // Create tag
    let body1 = json!({
        "tags": [{
            "id": tag_id,
            "name": "ToDelete",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body1).await;

    // Soft delete tag
    let body2 = json!({
        "tags": [{
            "id": tag_id,
            "name": "ToDelete",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": "2025-01-01T11:00:00"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body2).await;

    assert_eq!(status, StatusCode::OK);

    let tags = json.get("tags").unwrap().as_array().unwrap();
    assert_eq!(tags.len(), 1);
    assert!(tags[0].get("deletedAt").is_some());
    assert!(!tags[0].get("deletedAt").unwrap().is_null());
}

#[tokio::test]
async fn test_sync_push_creates_habit_tag_association() {
    let email = generate_email_from_fn!(test_sync_push_creates_habit_tag_association);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily workout",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Health",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    let habit_tags = json.get("habitTags").unwrap().as_array().unwrap();
    assert_eq!(habit_tags.len(), 1);
    assert_eq!(habit_tags[0].get("habitId").unwrap(), &habit_id);
    assert_eq!(habit_tags[0].get("tagId").unwrap(), &tag_id);
}

#[tokio::test]
async fn test_sync_push_soft_deletes_habit_tag_association() {
    let email = generate_email_from_fn!(test_sync_push_soft_deletes_habit_tag_association);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    // Create habit, tag, and association
    let body1 = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Health",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body1).await;

    // Soft delete association
    let body2 = json!({
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": "2025-01-01T11:00:00"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body2).await;

    assert_eq!(status, StatusCode::OK);

    let habit_tags = json.get("habitTags").unwrap().as_array().unwrap();
    assert_eq!(habit_tags.len(), 1);
    assert!(habit_tags[0].get("deletedAt").is_some());
    assert!(!habit_tags[0].get("deletedAt").unwrap().is_null());
}

#[tokio::test]
async fn test_sync_push_tag_validates_name_length() {
    let email = generate_email_from_fn!(test_sync_push_tag_validates_name_length);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();
    let long_name = "a".repeat(101);

    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": long_name,
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_push_tag_validates_color_hex_format() {
    let email = generate_email_from_fn!(test_sync_push_tag_validates_color_hex_format);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Test",
            "colorHex": "invalid",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_push_habit_tag_validates_habit_exists() {
    let email = generate_email_from_fn!(test_sync_push_habit_tag_validates_habit_exists);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let non_existent_habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Test",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": non_existent_habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error for non-existent habit reference"
    );
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_push_habit_tag_validates_tag_exists() {
    let email = generate_email_from_fn!(test_sync_push_habit_tag_validates_tag_exists);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let non_existent_tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": non_existent_tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error for non-existent tag reference"
    );
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_push_tag_idempotent() {
    let email = generate_email_from_fn!(test_sync_push_tag_idempotent);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let tag_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Work",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    // First push
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Second push with same data
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Verify only one tag exists
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_json.get("tags").unwrap().as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn test_sync_push_habit_tag_idempotent() {
    let email = generate_email_from_fn!(test_sync_push_habit_tag_idempotent);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Daily",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Health",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    // First push
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Second push with same data
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Verify only one association exists
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(
        pull_json
            .get("habitTags")
            .unwrap()
            .as_array()
            .unwrap()
            .len(),
        1
    );
}

#[tokio::test]
async fn test_sync_tags_data_isolation() {
    let email1 = "test_sync_tags_isolation_user1@test.com".to_string();
    let email2 = "test_sync_tags_isolation_user2@test.com".to_string();
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a tag
    let tag_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Private Tag",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&token1, "/api/v1/sync", body).await;

    // User 2 tries to pull
    let (status, json) = make_authenticated_get_request(&token2, "/api/v1/sync").await;
    dbg!(json.clone());
    assert_eq!(status, StatusCode::OK);

    // User 2 should not see User 1's tag
    assert_eq!(json.get("tags").unwrap().as_array().unwrap().len(), 0);
}

// ============================================================================
// Reward Sync Pull Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_includes_rewards() {
    let email = generate_email_from_fn!(test_sync_pull_includes_rewards);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create a reward via sync push
    let reward_id = uuid::Uuid::new_v4().to_string();
    let sync_body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Chocolate Bar",
            "description": "Eat a chocolate bar",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "maxDailyFrequency": 50.0,
            "damageTier": "light"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    // Now test GET /api/v1/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check rewards
    let rewards = json.get("rewards").unwrap().as_array().unwrap();
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].get("id").unwrap(), &reward_id);
    assert_eq!(rewards[0].get("name").unwrap(), "Chocolate Bar");
    assert_eq!(rewards[0].get("maxDailyFrequency").unwrap(), 50.0);
    assert_eq!(rewards[0].get("damageTier").unwrap(), "light");
}

#[tokio::test]
async fn test_sync_pull_includes_reward_tags() {
    let email = generate_email_from_fn!(test_sync_pull_includes_reward_tags);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create reward, tag, and association via sync push
    let reward_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let sync_body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Chocolate Bar",
            "description": "A treat",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Treats",
            "colorHex": "#FF5733FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "rewardTags": [{
            "rewardId": reward_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body).await;

    // Now test GET /api/v1/sync
    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);

    // Check rewardTags
    let reward_tags = json.get("rewardTags").unwrap().as_array().unwrap();
    assert_eq!(reward_tags.len(), 1);
    assert_eq!(reward_tags[0].get("rewardId").unwrap(), &reward_id);
    assert_eq!(reward_tags[0].get("tagId").unwrap(), &tag_id);
}

#[tokio::test]
async fn test_sync_pull_rewards_filtered_by_since() {
    let email = generate_email_from_fn!(test_sync_pull_rewards_filtered_by_since);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Create first reward
    let reward1_id = uuid::Uuid::new_v4().to_string();
    let sync_body1 = json!({
        "rewards": [{
            "id": reward1_id,
            "name": "Old Reward",
            "description": "Created before timestamp",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    let (_, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body1).await;
    let server_cursor = push_json
        .get("serverCursor")
        .unwrap()
        .as_str()
        .unwrap()
        .to_string();

    // Create second reward after getting timestamp
    let reward2_id = uuid::Uuid::new_v4().to_string();
    let sync_body2 = json!({
        "rewards": [{
            "id": reward2_id,
            "name": "New Reward",
            "description": "Created after timestamp",
            "createdAt": "2025-01-01T11:00:00",
            "updatedAt": "2025-01-01T11:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", sync_body2).await;

    // Pull since cursor - should only get new reward
    let url = format!(
        "/api/v1/sync?cursor={}",
        urlencoding::encode(&server_cursor)
    );
    let (status, json) = make_authenticated_get_request(&access_token, &url).await;

    assert_eq!(status, StatusCode::OK);

    let rewards = json.get("rewards").unwrap().as_array().unwrap();
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].get("id").unwrap(), &reward2_id);
    assert_eq!(rewards[0].get("name").unwrap(), "New Reward");
}

// ============================================================================
// Reward Sync Push Tests
// ============================================================================

#[tokio::test]
async fn test_sync_push_creates_reward() {
    let email = generate_email_from_fn!(test_sync_push_creates_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Chocolate Bar",
            "description": "A sweet treat",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "maxDailyFrequency": 25.0,
            "damageTier": "heavy"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    let rewards = json.get("rewards").unwrap().as_array().unwrap();
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].get("id").unwrap(), &reward_id);
    assert_eq!(rewards[0].get("name").unwrap(), "Chocolate Bar");
    assert_eq!(rewards[0].get("description").unwrap(), "A sweet treat");
    assert_eq!(rewards[0].get("maxDailyFrequency").unwrap(), 25.0);
    assert_eq!(rewards[0].get("damageTier").unwrap(), "heavy");
}

#[tokio::test]
async fn test_sync_push_updates_reward() {
    let email = generate_email_from_fn!(test_sync_push_updates_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();

    // Create reward
    let body1 = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Original",
            "description": "Original description",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body1).await;

    // Update reward
    let body2 = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Updated",
            "description": "Updated description",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "damageTier": "extreme"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body2).await;

    assert_eq!(status, StatusCode::OK);

    let rewards = json.get("rewards").unwrap().as_array().unwrap();
    assert_eq!(rewards.len(), 1);
    assert_eq!(rewards[0].get("name").unwrap(), "Updated");
    assert_eq!(
        rewards[0].get("description").unwrap(),
        "Updated description"
    );
    assert_eq!(rewards[0].get("damageTier").unwrap(), "extreme");
}

#[tokio::test]
async fn test_sync_push_soft_deletes_reward() {
    let email = generate_email_from_fn!(test_sync_push_soft_deletes_reward);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();

    // Create reward
    let body1 = json!({
        "rewards": [{
            "id": reward_id,
            "name": "ToDelete",
            "description": "Will be deleted",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body1).await;

    // Soft delete reward
    let body2 = json!({
        "rewards": [{
            "id": reward_id,
            "name": "ToDelete",
            "description": "Will be deleted",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T11:00:00",
            "deletedAt": "2025-01-01T11:00:00"
        }]
    });
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body2).await;

    assert_eq!(status, StatusCode::OK);

    let rewards = json.get("rewards").unwrap().as_array().unwrap();
    assert_eq!(rewards.len(), 1);
    assert!(rewards[0].get("deletedAt").is_some());
    assert!(!rewards[0].get("deletedAt").unwrap().is_null());
}

#[tokio::test]
async fn test_sync_push_creates_reward_tag_association() {
    let email = generate_email_from_fn!(test_sync_push_creates_reward_tag_association);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Chocolate Bar",
            "description": "A treat",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Treats",
            "colorHex": "#FF5733FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "rewardTags": [{
            "rewardId": reward_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);

    let reward_tags = json.get("rewardTags").unwrap().as_array().unwrap();
    assert_eq!(reward_tags.len(), 1);
    assert_eq!(reward_tags[0].get("rewardId").unwrap(), &reward_id);
    assert_eq!(reward_tags[0].get("tagId").unwrap(), &tag_id);
}

#[tokio::test]
async fn test_sync_push_reward_tag_validates_reward_exists() {
    let email = generate_email_from_fn!(test_sync_push_reward_tag_validates_reward_exists);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let non_existent_reward_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();

    let body = json!({
        "tags": [{
            "id": tag_id,
            "name": "Test",
            "colorHex": "#FF0000FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "rewardTags": [{
            "rewardId": non_existent_reward_id,
            "tagId": tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error for non-existent reward reference"
    );
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_push_reward_validates_name_length() {
    let email = generate_email_from_fn!(test_sync_push_reward_validates_name_length);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();
    let long_name = "a".repeat(101);

    let body = json!({
        "rewards": [{
            "id": reward_id,
            "name": long_name,
            "description": "Valid description",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(json.get("errors").is_some());
}

#[tokio::test]
async fn test_sync_rewards_data_isolation() {
    let email1 = "test_sync_rewards_isolation_user1@test.com".to_string();
    let email2 = "test_sync_rewards_isolation_user2@test.com".to_string();
    let password = "password123";

    register_user(&email1, password).await;
    register_user(&email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(&email2, &password).await;

    // User 1 creates a reward
    let reward_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Private Reward",
            "description": "Only for user 1",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });
    make_authenticated_post_request(&token1, "/api/v1/sync", body).await;

    // User 2 tries to pull
    let (status, json) = make_authenticated_get_request(&token2, "/api/v1/sync").await;
    assert_eq!(status, StatusCode::OK);

    // User 2 should not see User 1's reward
    assert_eq!(json.get("rewards").unwrap().as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn test_sync_push_reward_idempotent() {
    let email = generate_email_from_fn!(test_sync_push_reward_idempotent);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let reward_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "rewards": [{
            "id": reward_id,
            "name": "Chocolate",
            "description": "Sweet treat",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    // First push
    let (status, json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Second push with same data
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert!(json.get("errors").is_none());

    // Verify only one reward exists
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(
        pull_json.get("rewards").unwrap().as_array().unwrap().len(),
        1
    );
}

#[tokio::test]
async fn test_sync_push_atomicity_with_tags() {
    let email = generate_email_from_fn!(test_sync_push_atomicity_with_tags);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let tag_id = uuid::Uuid::new_v4().to_string();
    let trade_id = uuid::Uuid::new_v4().to_string();
    let non_existent_tag_id = uuid::Uuid::new_v4().to_string();

    // Try to create habit, tag, valid trade, but invalid habit_tag (references non-existent tag)
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Exercise",
            "description": "Should rollback",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "tags": [{
            "id": tag_id,
            "name": "Health",
            "colorHex": "#00FF00FF",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }],
        "trades": [{
            "id": trade_id,
            "habitId": habit_id,
            "amount": 500,
            "createdAt": "2025-01-01T10:00:00"
        }],
        "habitTags": [{
            "habitId": habit_id,
            "tagId": non_existent_tag_id,
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert!(
        status == StatusCode::BAD_REQUEST || status == StatusCode::INTERNAL_SERVER_ERROR,
        "Expected error for invalid habit_tag reference"
    );

    // Verify everything was rolled back
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(
        pull_json.get("habits").unwrap().as_array().unwrap().len(),
        0,
        "Habit should have been rolled back"
    );
    assert_eq!(
        pull_json.get("tags").unwrap().as_array().unwrap().len(),
        0,
        "Tag should have been rolled back"
    );
    assert_eq!(
        pull_json.get("trades").unwrap().as_array().unwrap().len(),
        0,
        "Trade should have been rolled back"
    );
}

// ============================================================================
// General Difficulty Tests
// ============================================================================

#[tokio::test]
async fn test_sync_pull_returns_default_general_difficulty() {
    let email = generate_email_from_fn!(test_sync_pull_returns_default_general_difficulty);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let (status, json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("generalDifficulty").unwrap(), 5.0);
}

#[tokio::test]
async fn test_sync_push_updates_general_difficulty() {
    let email = generate_email_from_fn!(test_sync_push_updates_general_difficulty);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Push a new general difficulty
    let body = json!({
        "generalDifficulty": 8.5
    });
    let (status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(push_json.get("generalDifficulty").unwrap(), 8.5);

    // Verify it persists via pull
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_json.get("generalDifficulty").unwrap(), 8.5);
}

#[tokio::test]
async fn test_sync_push_general_difficulty_validation_zero() {
    let email = generate_email_from_fn!(test_sync_push_general_difficulty_validation_zero);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "generalDifficulty": 0.0
    });
    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Verify default was not changed
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_json.get("generalDifficulty").unwrap(), 5.0);
}

#[tokio::test]
async fn test_sync_push_general_difficulty_validation_negative() {
    let email = generate_email_from_fn!(test_sync_push_general_difficulty_validation_negative);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "generalDifficulty": -1.0
    });
    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_sync_push_general_difficulty_validation_too_high() {
    let email = generate_email_from_fn!(test_sync_push_general_difficulty_validation_too_high);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let body = json!({
        "generalDifficulty": 1000.0
    });
    let (status, _) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_sync_push_general_difficulty_boundary_values() {
    let email = generate_email_from_fn!(test_sync_push_general_difficulty_boundary_values);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Just above zero should work
    let body = json!({
        "generalDifficulty": 0.01
    });
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("generalDifficulty").unwrap(), 0.01);

    // Just below 1000 should work
    let body = json!({
        "generalDifficulty": 999.99
    });
    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json.get("generalDifficulty").unwrap(), 999.99);
}

#[tokio::test]
async fn test_sync_push_general_difficulty_with_other_entities() {
    let email = generate_email_from_fn!(test_sync_push_general_difficulty_with_other_entities);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "generalDifficulty": 3.0,
        "habits": [{
            "id": habit_id,
            "name": "Test Habit",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00"
        }]
    });

    let (status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(push_json.get("generalDifficulty").unwrap(), 3.0);

    // Verify both the habit and difficulty persisted
    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    assert_eq!(pull_json.get("generalDifficulty").unwrap(), 3.0);
    assert_eq!(
        pull_json.get("habits").unwrap().as_array().unwrap().len(),
        1
    );
}

#[tokio::test]
async fn test_sync_push_habit_round_trips_duration_lockout_and_benefit() {
    let email =
        generate_email_from_fn!(test_sync_push_habit_round_trips_duration_lockout_and_benefit);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Stretch",
            "description": "Morning stretch",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "durationSeconds": 600,
            "lockoutDurationSeconds": 3600,
            "benefit": 5
        }]
    });

    let (status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    let habit = push_json
        .get("habits")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(habit.get("durationSeconds").unwrap(), 600);
    assert_eq!(habit.get("lockoutDurationSeconds").unwrap(), 3600);
    assert_eq!(habit.get("benefit").unwrap(), 5);

    let (_, pull_json) = make_authenticated_get_request(&access_token, "/api/v1/sync").await;
    let pulled_habit = pull_json
        .get("habits")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(pulled_habit.get("durationSeconds").unwrap(), 600);
    assert_eq!(pulled_habit.get("lockoutDurationSeconds").unwrap(), 3600);
    assert_eq!(pulled_habit.get("benefit").unwrap(), 5);
}

#[tokio::test]
async fn test_sync_push_habit_rejects_legacy_skip_consequence_field() {
    let email = generate_email_from_fn!(test_sync_push_habit_rejects_legacy_skip_consequence_field);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Legacy habit",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "skipConsequence": 5
        }]
    });

    let (status, _) =
        make_authenticated_post_request_raw(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn test_sync_push_habit_rejects_unknown_task_commitment_field() {
    let email = generate_email_from_fn!(test_sync_push_habit_rejects_unknown_task_commitment_field);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Bad habit",
            "description": "",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "commitment": 5
        }]
    });

    let (status, _) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_sync_push_habit_validates_duration_range() {
    let email = generate_email_from_fn!(test_sync_push_habit_validates_duration_range);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Stretch",
            "description": "Morning stretch",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "durationSeconds": 43201
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let error = json
        .get("errors")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'duration_seconds' must be between 1 and 43200. You sent 43201."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_sync_push_habit_validates_lockout_duration_range() {
    let email = generate_email_from_fn!(test_sync_push_habit_validates_lockout_duration_range);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Stretch",
            "description": "Morning stretch",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "lockoutDurationSeconds": 59
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let error = json
        .get("errors")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'lockout_duration_seconds' must be between 60 and 2592000. You sent 59."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_sync_push_habit_validates_lockout_duration_maximum() {
    let email = generate_email_from_fn!(test_sync_push_habit_validates_lockout_duration_maximum);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Stretch",
            "description": "Morning stretch",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "lockoutDurationSeconds": 2_592_001
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let error = json
        .get("errors")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'lockout_duration_seconds' must be between 60 and 2592000. You sent 2592001."
                .to_string()
        )
    );
}

#[tokio::test]
async fn test_sync_push_habit_validates_benefit_range() {
    let email = generate_email_from_fn!(test_sync_push_habit_validates_benefit_range);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    let habit_id = uuid::Uuid::new_v4().to_string();
    let body = json!({
        "habits": [{
            "id": habit_id,
            "name": "Stretch",
            "description": "Morning stretch",
            "createdAt": "2025-01-01T10:00:00",
            "updatedAt": "2025-01-01T10:00:00",
            "benefit": 0
        }]
    });

    let (status, json) = make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    let error = json
        .get("errors")
        .unwrap()
        .as_array()
        .unwrap()
        .first()
        .unwrap();
    assert_eq!(
        error.get("message").unwrap(),
        &Value::String(
            "Validation Error: The 'benefit' must be between 1 and 5. You sent 0.".to_string()
        )
    );
}

#[tokio::test]
async fn test_sync_push_without_general_difficulty_preserves_existing() {
    let email =
        generate_email_from_fn!(test_sync_push_without_general_difficulty_preserves_existing);
    let password = "password123";

    register_user(&email, password).await;
    let access_token = get_access_token_for_user(&email, &password).await;

    // Set difficulty to 7.0
    let body = json!({
        "generalDifficulty": 7.0
    });
    make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    // Push without generalDifficulty
    let body = json!({});
    let (status, push_json) =
        make_authenticated_post_request(&access_token, "/api/v1/sync", body).await;

    assert_eq!(status, StatusCode::OK);
    // Should still return 7.0
    assert_eq!(push_json.get("generalDifficulty").unwrap(), 7.0);
}

#[tokio::test]
async fn test_sync_general_difficulty_isolation_between_users() {
    let email1 = generate_email_from_fn!(test_sync_general_difficulty_isolation_between_users);
    let email2 = "test_sync_gd_isolation_user2@test.com";
    let password = "password123";

    register_user(&email1, password).await;
    register_user(email2, password).await;
    let token1 = get_access_token_for_user(&email1, &password).await;
    let token2 = get_access_token_for_user(email2, &password).await;

    // User 1 sets difficulty to 2.0
    let body = json!({ "generalDifficulty": 2.0 });
    make_authenticated_post_request(&token1, "/api/v1/sync", body).await;

    // User 2 should still have default 5.0
    let (_, pull_json) = make_authenticated_get_request(&token2, "/api/v1/sync").await;
    assert_eq!(pull_json.get("generalDifficulty").unwrap(), 5.0);

    // User 1 should still have 2.0
    let (_, pull_json) = make_authenticated_get_request(&token1, "/api/v1/sync").await;
    assert_eq!(pull_json.get("generalDifficulty").unwrap(), 2.0);
}
