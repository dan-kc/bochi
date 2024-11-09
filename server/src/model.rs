use async_graphql::{Context, EmptyMutation, EmptySubscription, Object, Schema};

pub type ServiceSchema = Schema<QueryRoot, EmptyMutation, EmptySubscription>;

pub struct QueryRoot;

#[Object]
impl QueryRoot {
    async fn hello(&self, _ctx: &Context<'_>) -> &'static str {
        "Wag1"
    }
}
