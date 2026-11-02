use std::env;
use std::error::Error;

use sqlx::postgres::PgPoolOptions;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());

    let pool = PgPoolOptions::new()
        .max_connections(16)
        .connect(&database_url)
        .await?;
    arcanum_server::migrate(&pool).await?;
    let app = arcanum_server::app(pool).await?;

    let listener = TcpListener::bind(&bind).await?;
    tracing::info!("listening on {bind} (put a TLS-terminating proxy in front)");
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
