use arcanum_proto::{ErrorCode, ErrorResponse};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;

#[derive(Debug)]
pub struct ApiError {
    status: StatusCode,
    code: ErrorCode,
    message: String,
}

pub type ApiResult<T> = Result<T, ApiError>;

impl ApiError {
    fn new(status: StatusCode, code: ErrorCode, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
        }
    }

    pub fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, ErrorCode::BadRequest, message)
    }

    pub fn unauthorized() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            ErrorCode::Unauthorized,
            "authentication required",
        )
    }

    /// Same answer for unknown email and wrong credentials.
    pub fn invalid_login() -> Self {
        Self::new(
            StatusCode::UNAUTHORIZED,
            ErrorCode::InvalidLogin,
            "invalid email or password",
        )
    }

    pub fn email_taken() -> Self {
        Self::new(
            StatusCode::CONFLICT,
            ErrorCode::EmailTaken,
            "an account with this email already exists",
        )
    }

    pub fn not_found() -> Self {
        Self::new(StatusCode::NOT_FOUND, ErrorCode::NotFound, "not found")
    }

    pub fn too_many_requests() -> Self {
        Self::new(
            StatusCode::TOO_MANY_REQUESTS,
            ErrorCode::TooManyRequests,
            "too many attempts, try again later",
        )
    }

    pub fn cursor_ahead() -> Self {
        Self::new(
            StatusCode::CONFLICT,
            ErrorCode::CursorAhead,
            "sync cursor is ahead of the server, resync from scratch",
        )
    }

    pub fn internal(detail: impl std::fmt::Display) -> Self {
        tracing::error!("internal error: {detail}");
        Self::new(
            StatusCode::INTERNAL_SERVER_ERROR,
            ErrorCode::Internal,
            "internal error",
        )
    }
}

impl From<sqlx::Error> for ApiError {
    fn from(e: sqlx::Error) -> Self {
        Self::internal(e)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(ErrorResponse {
                error: self.code,
                message: self.message,
            }),
        )
            .into_response()
    }
}
