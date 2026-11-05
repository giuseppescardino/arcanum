use std::env;
use std::error::Error;
use std::net::SocketAddr;
use std::process::ExitCode;

use arcanum_server::{admin, Config};
use sqlx::postgres::PgPoolOptions;
use sqlx::PgPool;
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args: Vec<String> = env::args().skip(1).collect();
    let result = if admin::is_admin_command(&args) {
        run_admin(&args).await
    } else if args.is_empty() {
        serve().await
    } else {
        Err(admin::USAGE.into())
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}");
            ExitCode::FAILURE
        }
    }
}

async fn connect(max: u32) -> Result<PgPool, Box<dyn Error>> {
    let database_url = env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is not set")?;
    let pool = PgPoolOptions::new()
        .max_connections(max)
        .connect(&database_url)
        .await?;
    arcanum_server::migrate(&pool).await?;
    Ok(pool)
}

async fn run_admin(args: &[String]) -> Result<(), Box<dyn Error>> {
    let pool = connect(2).await?;
    let out = admin::run(&pool, args).await?;
    println!("{}", out.trim_end());
    Ok(())
}

async fn serve() -> Result<(), Box<dyn Error>> {
    let config = Config::from_env()?;
    let bind = env::var("BIND_ADDR").unwrap_or_else(|_| "0.0.0.0:8080".into());
    let pool = connect(16).await?;
    tracing::info!(
        registration = config.registration.as_str(),
        max_items_per_account = config.max_items_per_account,
        trust_proxy = config.trust_proxy,
        "configuration"
    );
    let app = arcanum_server::app(pool, config).await?;

    let listener = TcpListener::bind(&bind).await?;
    tracing::info!("listening on {bind} (put a TLS-terminating proxy in front)");
    // The peer address is the client IP when no proxy is trusted.
    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await?;
    Ok(())
}
