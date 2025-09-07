use http::StatusCode;

use crate::common::{get_access_token_for_user, make_authenticated_graphql_request, register_user};
use crate::generate_email_from_fn;
use serde_json::json;

#[tokio::test]
async fn test_introspection() {
    let email = generate_email_from_fn!(test_create_task_validation_difficulty_rank_negative);
    let password = "password123";

    // Register user
    register_user(&email, password).await;

    let access_token = get_access_token_for_user(&email, &password).await;

    let query = json!({
        "query": "
          {
            __schema {
              types {
                name
              }
            }
          }
        ",
    });

    let (status, _) = make_authenticated_graphql_request(&access_token, query).await;

    assert_eq!(status, StatusCode::OK);
}
