use base64::{
    engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
    Engine,
};
use chrono::{NaiveDateTime, Utc};
use jsonwebtoken::{
    decode, decode_header, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation,
};
use rustls_pki_types::{CertificateDer, UnixTime};
use serde::de::DeserializeOwned;
use sha2::{Digest, Sha256};
use tracing::{error, info, warn};
use webpki::EndEntityCert;

pub const APPLE_LIFETIME_PRODUCT_ID: &str = "lifetime.membership";
pub const APPLE_MONTHLY_PRODUCT_ID: &str = "monthly.membership";
pub const APPLE_YEARLY_PRODUCT_ID: &str = "annual.membership";
const APPLE_ROOT_CA_G3_DER_BASE64: &str = "MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==";
const APPLE_JWS_LEAF_EXTENSION_OID: &[u64] = &[1, 2, 840, 113635, 100, 6, 11, 1];
const APPLE_JWS_INTERMEDIATE_EXTENSION_OID: &[u64] = &[1, 2, 840, 113635, 100, 6, 2, 1];
const EKU_CODE_SIGNING: &[u8] = &[0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x03];

#[derive(Debug, thiserror::Error)]
pub enum AppleBillingError {
    #[error("Apple billing payload is invalid")]
    InvalidPayload,
    #[error("Apple billing product is invalid")]
    InvalidProduct,
    #[error("Apple billing environment is invalid")]
    InvalidEnvironment,
    #[error("Apple billing verification is unavailable")]
    VerificationUnavailable,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerifiedAppleTransaction {
    pub original_transaction_id: String,
    pub transaction_id: String,
    pub product_id: String,
    pub environment: String,
    pub expires_at: Option<NaiveDateTime>,
    pub is_revoked: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct VerifiedAppleRenewalInfo {
    pub original_transaction_id: String,
    pub product_id: Option<String>,
    pub environment: Option<String>,
    pub grace_period_expires_at: Option<NaiveDateTime>,
    pub renewal_date: Option<NaiveDateTime>,
}

#[derive(Debug)]
pub struct VerifiedAppleNotification {
    pub notification_uuid: String,
    pub notification_type: Option<String>,
    pub subtype: Option<String>,
    pub transaction: Option<VerifiedAppleTransaction>,
    pub renewal_info: Option<VerifiedAppleRenewalInfo>,
    pub signed_at: NaiveDateTime,
    pub payload_hash: String,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct TransactionInfoResponse {
    signed_transaction_info: String,
}

#[derive(serde::Serialize)]
struct AppStoreServerClaims {
    iss: String,
    iat: i64,
    exp: i64,
    aud: String,
    bid: String,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppleTransactionPayload {
    original_transaction_id: Option<String>,
    transaction_id: Option<String>,
    product_id: Option<String>,
    environment: Option<String>,
    expires_date: Option<i64>,
    revocation_date: Option<i64>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppleRenewalInfoPayload {
    original_transaction_id: Option<String>,
    product_id: Option<String>,
    environment: Option<String>,
    grace_period_expires_date: Option<i64>,
    renewal_date: Option<i64>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppleNotificationPayload {
    #[serde(rename = "notificationUUID")]
    notification_uuid: Option<String>,
    notification_type: Option<String>,
    subtype: Option<String>,
    signed_date: Option<i64>,
    data: Option<AppleNotificationData>,
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppleNotificationData {
    signed_transaction_info: Option<String>,
    signed_renewal_info: Option<String>,
}

pub fn is_apple_premium_product_id(product_id: &str) -> bool {
    matches!(
        product_id,
        APPLE_LIFETIME_PRODUCT_ID | APPLE_MONTHLY_PRODUCT_ID | APPLE_YEARLY_PRODUCT_ID
    )
}

pub fn normalize_apple_environment(value: &str) -> Option<&'static str> {
    match value.trim().to_ascii_lowercase().as_str() {
        "xcode" => Some("xcode"),
        "sandbox" => Some("sandbox"),
        "production" => Some("production"),
        _ => None,
    }
}

pub fn status_for_apple_transaction(
    transaction: &VerifiedAppleTransaction,
    notification_type: Option<&str>,
    subtype: Option<&str>,
) -> &'static str {
    let notification_type = notification_type.map(str::trim);
    let subtype = subtype.map(str::trim);

    if matches!(notification_type, Some("REFUND_REVERSED")) {
        return status_from_expiration(transaction);
    }

    if matches!(notification_type, Some("EXPIRED")) {
        return "expired";
    }

    if matches!(notification_type, Some("GRACE_PERIOD_EXPIRED")) {
        return "billing_retry";
    }

    if transaction.is_revoked || matches!(notification_type, Some("REFUND" | "REVOKE")) {
        return "revoked";
    }

    if matches!(notification_type, Some("DID_FAIL_TO_RENEW")) {
        return if matches!(subtype, Some("GRACE_PERIOD")) {
            "grace_period"
        } else {
            "billing_retry"
        };
    }

    status_from_expiration(transaction)
}

pub fn entitlement_expires_at_for_apple_notification(
    transaction: &VerifiedAppleTransaction,
    renewal_info: Option<&VerifiedAppleRenewalInfo>,
    notification_type: Option<&str>,
    subtype: Option<&str>,
) -> Option<NaiveDateTime> {
    let subscription_status = status_for_apple_transaction(transaction, notification_type, subtype);

    if subscription_status == "grace_period" {
        return renewal_info
            .and_then(|info| info.grace_period_expires_at)
            .or_else(|| renewal_info.and_then(|info| info.renewal_date))
            .or(transaction.expires_at);
    }

    transaction
        .expires_at
        .or_else(|| renewal_info.and_then(|info| info.renewal_date))
}

fn status_from_expiration(transaction: &VerifiedAppleTransaction) -> &'static str {
    if transaction
        .expires_at
        .map(|expires_at| expires_at <= Utc::now().naive_utc())
        .unwrap_or(false)
    {
        return "expired";
    }

    "active"
}

pub fn verify_linked_transaction(
    transaction_id: &str,
    original_transaction_id: &str,
    product_id: &str,
    environment: &str,
    client_expires_at: Option<NaiveDateTime>,
) -> Result<VerifiedAppleTransaction, AppleBillingError> {
    if !is_apple_premium_product_id(product_id) {
        return Err(AppleBillingError::InvalidProduct);
    }

    let normalized_environment =
        normalize_apple_environment(environment).ok_or(AppleBillingError::InvalidEnvironment)?;

    if normalized_environment == "xcode" {
        if std::env::var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS")
            .ok()
            .as_deref()
            != Some("true")
        {
            warn!(
                operation = "billing.verify_linked_transaction",
                apple_environment = normalized_environment,
                apple_transaction_id_hash = %log_value_hash(transaction_id),
                "insecure xcode Apple billing transactions are disabled"
            );
            return Err(AppleBillingError::VerificationUnavailable);
        }

        return Ok(VerifiedAppleTransaction {
            original_transaction_id: original_transaction_id.to_string(),
            transaction_id: transaction_id.to_string(),
            product_id: product_id.to_string(),
            environment: normalized_environment.to_string(),
            expires_at: client_expires_at,
            is_revoked: false,
        });
    }

    let signed_transaction_info = fetch_transaction_info(transaction_id, normalized_environment)?;
    let transaction = decode_apple_jws_payload::<AppleTransactionPayload>(&signed_transaction_info)
        .map_err(|error| {
            warn!(
                operation = "billing.verify_linked_transaction.decode_signed_transaction",
                apple_environment = normalized_environment,
                apple_transaction_id_hash = %log_value_hash(transaction_id),
                apple_signed_transaction_info_hash = %log_value_hash(signed_transaction_info.as_str()),
                error = ?error,
                "failed to decode App Store signed transaction"
            );
            error
        })
        .and_then(|payload| {
            VerifiedAppleTransaction::try_from(payload).map_err(|error| {
                warn!(
                    operation = "billing.verify_linked_transaction.validate_signed_transaction",
                    apple_environment = normalized_environment,
                    apple_transaction_id_hash = %log_value_hash(transaction_id),
                    apple_signed_transaction_info_hash = %log_value_hash(signed_transaction_info.as_str()),
                    error = ?error,
                    "App Store signed transaction payload failed validation"
                );
                error
            })
        })?;

    let transaction_id_matches = transaction.transaction_id == transaction_id;
    let original_transaction_id_matches =
        transaction.original_transaction_id == original_transaction_id;
    let product_id_matches = transaction.product_id == product_id;
    let environment_matches = transaction.environment == normalized_environment;

    info!(
        operation = "billing.verify_linked_transaction.apple_payload_decoded",
        client_apple_transaction_id_hash = %log_value_hash(transaction_id),
        apple_transaction_id_hash = %log_value_hash(transaction.transaction_id.as_str()),
        client_apple_original_transaction_id_hash = %log_value_hash(original_transaction_id),
        apple_original_transaction_id_hash = %log_value_hash(transaction.original_transaction_id.as_str()),
        client_apple_product_id = product_id,
        apple_product_id = transaction.product_id.as_str(),
        client_apple_environment = normalized_environment,
        apple_environment = transaction.environment.as_str(),
        apple_expires_at = ?transaction.expires_at,
        apple_is_revoked = transaction.is_revoked,
        transaction_id_matches,
        original_transaction_id_matches,
        product_id_matches,
        environment_matches,
        "App Store transaction payload decoded"
    );

    if !transaction_id_matches
        || !original_transaction_id_matches
        || !product_id_matches
        || !environment_matches
    {
        warn!(
            operation = "billing.verify_linked_transaction.payload_mismatch",
            client_apple_transaction_id_hash = %log_value_hash(transaction_id),
            apple_transaction_id_hash = %log_value_hash(transaction.transaction_id.as_str()),
            client_apple_original_transaction_id_hash = %log_value_hash(original_transaction_id),
            apple_original_transaction_id_hash = %log_value_hash(transaction.original_transaction_id.as_str()),
            client_apple_product_id = product_id,
            apple_product_id = transaction.product_id.as_str(),
            client_apple_environment = normalized_environment,
            apple_environment = transaction.environment.as_str(),
            apple_expires_at = ?transaction.expires_at,
            apple_is_revoked = transaction.is_revoked,
            transaction_id_matches,
            original_transaction_id_matches,
            product_id_matches,
            environment_matches,
            "App Store transaction payload did not match link request"
        );
        return Err(AppleBillingError::InvalidPayload);
    }

    Ok(transaction)
}

pub fn verify_apple_notification(
    signed_payload: &str,
) -> Result<VerifiedAppleNotification, AppleBillingError> {
    let payload_hash = hash_payload(signed_payload);
    let payload = decode_apple_jws_payload::<AppleNotificationPayload>(signed_payload)?;
    let notification_uuid = payload
        .notification_uuid
        .filter(|value| !value.trim().is_empty())
        .ok_or(AppleBillingError::InvalidPayload)?;
    let signed_at = payload
        .signed_date
        .and_then(naive_datetime_from_millis)
        .ok_or(AppleBillingError::InvalidPayload)?;
    let data = payload.data;

    let transaction = data
        .as_ref()
        .and_then(|data| data.signed_transaction_info.as_deref())
        .map(|signed_transaction| {
            decode_apple_jws_payload::<AppleTransactionPayload>(signed_transaction)
                .and_then(VerifiedAppleTransaction::try_from)
        })
        .transpose()?;
    let renewal_info = data
        .as_ref()
        .and_then(|data| data.signed_renewal_info.as_deref())
        .map(|signed_renewal_info| {
            decode_apple_jws_payload::<AppleRenewalInfoPayload>(signed_renewal_info)
                .and_then(VerifiedAppleRenewalInfo::try_from)
        })
        .transpose()?;

    if let (Some(transaction), Some(renewal_info)) = (&transaction, &renewal_info) {
        if transaction.original_transaction_id != renewal_info.original_transaction_id {
            return Err(AppleBillingError::InvalidPayload);
        }
    }

    Ok(VerifiedAppleNotification {
        notification_uuid,
        notification_type: payload.notification_type,
        subtype: payload.subtype,
        transaction,
        renewal_info,
        signed_at,
        payload_hash,
    })
}

fn fetch_transaction_info(
    transaction_id: &str,
    environment: &str,
) -> Result<String, AppleBillingError> {
    let (base_url, request_host) = match environment {
        "sandbox" => (
            "https://api.storekit-sandbox.apple.com/inApps/v1/transactions",
            "api.storekit-sandbox.apple.com",
        ),
        "production" => (
            "https://api.storekit.apple.com/inApps/v1/transactions",
            "api.storekit.apple.com",
        ),
        _ => return Err(AppleBillingError::InvalidEnvironment),
    };
    let token = create_app_store_server_token()?;
    let url = format!("{}/{}", base_url, transaction_id);

    info!(
        operation = "billing.fetch_transaction_info.request",
        apple_request_method = "GET",
        apple_request_host = request_host,
        apple_request_path_template = "/inApps/v1/transactions/{transactionId}",
        apple_request_url_template = %format!("{}/{{transactionId}}", base_url),
        apple_environment = environment,
        apple_transaction_id_hash = %log_value_hash(transaction_id),
        apple_authorization = "Bearer <redacted>",
        "requesting App Store transaction info"
    );

    let response = match ureq::get(url.as_str())
        .set("Authorization", format!("Bearer {}", token).as_str())
        .call()
    {
        Ok(response) => response,
        Err(ureq::Error::Status(status, response)) => {
            let body = response.into_string().ok();
            let body_hash = body.as_deref().map(log_value_hash);
            let body_preview = body.as_deref().map(log_response_body_preview);
            warn!(
                operation = "billing.fetch_transaction_info.response_error",
                apple_request_method = "GET",
                apple_request_host = request_host,
                apple_request_path_template = "/inApps/v1/transactions/{transactionId}",
                apple_request_url_template = %format!("{}/{{transactionId}}", base_url),
                apple_environment = environment,
                apple_transaction_id_hash = %log_value_hash(transaction_id),
                apple_response_status = status,
                apple_response_body_hash = body_hash.as_deref(),
                apple_response_body_preview = body_preview.as_deref(),
                "App Store transaction info request returned an error"
            );
            return Err(AppleBillingError::VerificationUnavailable);
        }
        Err(error) => {
            error!(
                operation = "billing.fetch_transaction_info",
                apple_request_method = "GET",
                apple_request_host = request_host,
                apple_request_path_template = "/inApps/v1/transactions/{transactionId}",
                apple_request_url_template = %format!("{}/{{transactionId}}", base_url),
                apple_environment = environment,
                apple_transaction_id_hash = %log_value_hash(transaction_id),
                error = ?error,
                "failed to fetch App Store transaction info"
            );
            return Err(AppleBillingError::VerificationUnavailable);
        }
    };
    let response_status = response.status();

    info!(
        operation = "billing.fetch_transaction_info.response",
        apple_request_method = "GET",
        apple_request_host = request_host,
        apple_request_path_template = "/inApps/v1/transactions/{transactionId}",
        apple_request_url_template = %format!("{}/{{transactionId}}", base_url),
        apple_environment = environment,
        apple_transaction_id_hash = %log_value_hash(transaction_id),
        apple_response_status = response_status,
        "App Store transaction info response received"
    );

    let body = response.into_string().map_err(|error| {
        error!(
            operation = "billing.read_transaction_info_response",
            apple_environment = environment,
            apple_transaction_id_hash = %log_value_hash(transaction_id),
            error = ?error,
            "failed to read App Store transaction info response"
        );
        AppleBillingError::VerificationUnavailable
    })?;
    let body_hash = log_value_hash(body.as_str());
    let response: TransactionInfoResponse =
        serde_json::from_str(body.as_str()).map_err(|error| {
            warn!(
                operation = "billing.decode_transaction_info_response",
                apple_environment = environment,
                apple_transaction_id_hash = %log_value_hash(transaction_id),
                apple_response_body_hash = %body_hash,
                apple_response_body_preview = %log_response_body_preview(body.as_str()),
                error = ?error,
                "App Store transaction info response had invalid payload"
            );
            AppleBillingError::InvalidPayload
        })?;

    info!(
        operation = "billing.decode_transaction_info_response",
        apple_environment = environment,
        apple_transaction_id_hash = %log_value_hash(transaction_id),
        apple_response_body_hash = %body_hash,
        apple_signed_transaction_info_hash = %log_value_hash(response.signed_transaction_info.as_str()),
        "App Store transaction info response decoded"
    );

    Ok(response.signed_transaction_info)
}

fn create_app_store_server_token() -> Result<String, AppleBillingError> {
    let issuer_id = app_store_env_var("APP_STORE_SERVER_ISSUER_ID")?;
    let key_id = app_store_env_var("APP_STORE_SERVER_KEY_ID")?;
    let bundle_id = app_store_env_var("APP_STORE_SERVER_BUNDLE_ID")?;
    let private_key = app_store_env_var("APP_STORE_SERVER_PRIVATE_KEY")?;
    let issued_at = Utc::now().timestamp();
    let claims = AppStoreServerClaims {
        iss: issuer_id,
        iat: issued_at,
        exp: issued_at + 20 * 60,
        aud: "appstoreconnect-v1".to_string(),
        bid: bundle_id,
    };
    let mut header = Header::new(Algorithm::ES256);
    header.kid = Some(key_id);

    encode(
        &header,
        &claims,
        &EncodingKey::from_ec_pem(private_key.as_bytes()).map_err(|error| {
            error!(
                operation = "billing.create_app_store_server_token",
                error = ?error,
                "failed to parse App Store private key"
            );
            AppleBillingError::VerificationUnavailable
        })?,
    )
    .map_err(|error| {
        error!(
            operation = "billing.create_app_store_server_token",
            error = ?error,
            "failed to sign App Store server token"
        );
        AppleBillingError::VerificationUnavailable
    })
}

fn app_store_env_var(name: &'static str) -> Result<String, AppleBillingError> {
    std::env::var(name).map_err(|error| {
        error!(
            operation = "billing.read_app_store_configuration",
            env_var = name,
            error = ?error,
            "missing App Store server configuration"
        );
        AppleBillingError::VerificationUnavailable
    })
}

fn decode_apple_jws_payload<T: DeserializeOwned>(
    signed_payload: &str,
) -> Result<T, AppleBillingError> {
    if let Some(test_payload) = decode_test_jws_payload::<T>(signed_payload)? {
        return Ok(test_payload);
    }

    let signed_payload_hash = log_value_hash(signed_payload);
    let header = decode_header(signed_payload).map_err(|error| {
        warn!(
            operation = "billing.decode_apple_jws_payload.decode_header",
            apple_signed_payload_hash = %signed_payload_hash,
            error = ?error,
            "failed to decode Apple JWS header"
        );
        AppleBillingError::InvalidPayload
    })?;
    let x5c_count = header.x5c.as_ref().map(Vec::len);
    info!(
        operation = "billing.decode_apple_jws_payload.header_decoded",
        apple_signed_payload_hash = %signed_payload_hash,
        apple_jws_alg = ?header.alg,
        apple_jws_x5c_count = ?x5c_count,
        "Apple JWS header decoded"
    );
    if header.alg != Algorithm::ES256 {
        warn!(
            operation = "billing.decode_apple_jws_payload.invalid_algorithm",
            apple_signed_payload_hash = %signed_payload_hash,
            apple_jws_alg = ?header.alg,
            "Apple JWS used an unsupported signing algorithm"
        );
        return Err(AppleBillingError::InvalidPayload);
    }
    let certificates = header
        .x5c_der()
        .map_err(|error| {
            warn!(
                operation = "billing.decode_apple_jws_payload.decode_x5c",
                apple_signed_payload_hash = %signed_payload_hash,
                apple_jws_x5c_count = ?x5c_count,
                error = ?error,
                "failed to decode Apple JWS certificate chain"
            );
            AppleBillingError::InvalidPayload
        })?
        .ok_or_else(|| {
            warn!(
                operation = "billing.decode_apple_jws_payload.missing_x5c",
                apple_signed_payload_hash = %signed_payload_hash,
                "Apple JWS header did not include a certificate chain"
            );
            AppleBillingError::InvalidPayload
        })?;
    let public_key = verified_apple_jws_public_key(certificates.as_slice())?;
    let mut validation = Validation::new(Algorithm::ES256);
    validation.required_spec_claims.clear();
    validation.validate_exp = false;
    validation.validate_aud = false;

    decode::<T>(
        signed_payload,
        &DecodingKey::from_ec_der(public_key.as_slice()),
        &validation,
    )
    .map(|data| data.claims)
    .map_err(|error| {
        warn!(
            operation = "billing.decode_apple_jws_payload.verify_signature_or_claims",
            apple_signed_payload_hash = %signed_payload_hash,
            error = ?error,
            "failed to verify Apple JWS signature or decode claims"
        );
        AppleBillingError::InvalidPayload
    })
}

fn decode_test_jws_payload<T: DeserializeOwned>(
    signed_payload: &str,
) -> Result<Option<T>, AppleBillingError> {
    let Some(encoded) = signed_payload.strip_prefix("test-jws:") else {
        return Ok(None);
    };
    if std::env::var("ALLOW_INSECURE_APPLE_BILLING_TEST_TRANSACTIONS")
        .ok()
        .as_deref()
        != Some("true")
    {
        return Err(AppleBillingError::InvalidPayload);
    }

    let bytes = URL_SAFE_NO_PAD
        .decode(encoded)
        .map_err(|_| AppleBillingError::InvalidPayload)?;
    serde_json::from_slice(bytes.as_slice())
        .map(Some)
        .map_err(|_| AppleBillingError::InvalidPayload)
}

fn verified_apple_jws_public_key(certificates: &[Vec<u8>]) -> Result<Vec<u8>, AppleBillingError> {
    if certificates.len() != 3 {
        warn!(
            operation = "billing.verified_apple_jws_public_key.invalid_chain_length",
            apple_jws_certificate_count = certificates.len(),
            "Apple JWS certificate chain length was invalid"
        );
        return Err(AppleBillingError::InvalidPayload);
    }

    let leaf_certificate = certificates
        .first()
        .ok_or(AppleBillingError::InvalidPayload)?;
    let intermediate_certificate = certificates
        .get(1)
        .ok_or(AppleBillingError::InvalidPayload)?;

    let leaf_has_required_oid = der_contains_oid(leaf_certificate, APPLE_JWS_LEAF_EXTENSION_OID);
    let intermediate_has_required_oid = der_contains_oid(
        intermediate_certificate,
        APPLE_JWS_INTERMEDIATE_EXTENSION_OID,
    );
    if !leaf_has_required_oid || !intermediate_has_required_oid {
        warn!(
            operation = "billing.verified_apple_jws_public_key.missing_required_oid",
            apple_leaf_has_required_oid = leaf_has_required_oid,
            apple_intermediate_has_required_oid = intermediate_has_required_oid,
            "Apple JWS certificate chain was missing required Apple extensions"
        );
        return Err(AppleBillingError::InvalidPayload);
    }

    let root_certificate = CertificateDer::from(
        STANDARD
            .decode(APPLE_ROOT_CA_G3_DER_BASE64)
            .map_err(|error| {
                error!(
                    operation = "billing.verified_apple_jws_public_key.decode_root",
                    error = ?error,
                    "failed to decode configured Apple root certificate"
                );
                AppleBillingError::InvalidPayload
            })?,
    );
    let trust_anchor = webpki::anchor_from_trusted_cert(&root_certificate).map_err(|error| {
        error!(
            operation = "billing.verified_apple_jws_public_key.parse_root",
            error = ?error,
            "failed to parse configured Apple root certificate"
        );
        AppleBillingError::InvalidPayload
    })?;
    let trust_anchors = [trust_anchor];
    let intermediate_certificate = CertificateDer::from(intermediate_certificate.clone());
    let intermediates = [intermediate_certificate];
    let leaf_certificate = CertificateDer::from(leaf_certificate.clone());
    let certificate = EndEntityCert::try_from(&leaf_certificate).map_err(|error| {
        warn!(
            operation = "billing.verified_apple_jws_public_key.parse_leaf",
            error = ?error,
            "failed to parse Apple JWS leaf certificate"
        );
        AppleBillingError::InvalidPayload
    })?;

    certificate
        .verify_for_usage(
            webpki::ALL_VERIFICATION_ALGS,
            &trust_anchors,
            &intermediates,
            UnixTime::now(),
            webpki::KeyUsage::required_if_present(EKU_CODE_SIGNING),
            None,
            None,
        )
        .map_err(|error| {
            warn!(
                operation = "billing.verified_apple_jws_public_key.verify_chain",
                error = ?error,
                "failed to verify Apple JWS certificate chain"
            );
            AppleBillingError::InvalidPayload
        })?;

    ec_public_key_from_subject_public_key_info(certificate.subject_public_key_info().as_ref())
}

fn ec_public_key_from_subject_public_key_info(
    subject_public_key_info: &[u8],
) -> Result<Vec<u8>, AppleBillingError> {
    const EC_PUBLIC_KEY_P256_PREFIX: &[u8] = &[
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08,
        0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
    ];

    let Some(public_key) = subject_public_key_info.strip_prefix(EC_PUBLIC_KEY_P256_PREFIX) else {
        warn!(
            operation = "billing.ec_public_key_from_subject_public_key_info.invalid_spki",
            apple_subject_public_key_info_hash = %log_value_hash(&STANDARD.encode(subject_public_key_info)),
            apple_subject_public_key_info_len = subject_public_key_info.len(),
            "Apple JWS leaf certificate used an unsupported EC public key format"
        );
        return Err(AppleBillingError::InvalidPayload);
    };

    if public_key.len() != 65 || public_key.first() != Some(&0x04) {
        warn!(
            operation = "billing.ec_public_key_from_subject_public_key_info.invalid_key",
            apple_public_key_hash = %log_value_hash(&STANDARD.encode(public_key)),
            apple_public_key_len = public_key.len(),
            "Apple JWS leaf certificate used an invalid P-256 public key"
        );
        return Err(AppleBillingError::InvalidPayload);
    }

    Ok(public_key.to_vec())
}

fn der_contains_oid(certificate_der: &[u8], oid: &[u64]) -> bool {
    let Some(encoded_oid) = der_encoded_oid(oid) else {
        return false;
    };

    certificate_der
        .windows(encoded_oid.len())
        .any(|window| window == encoded_oid.as_slice())
}

fn der_encoded_oid(oid: &[u64]) -> Option<Vec<u8>> {
    if oid.len() < 2 || oid[0] > 2 || (oid[0] < 2 && oid[1] >= 40) {
        return None;
    }

    let mut value = Vec::new();
    push_oid_component(oid[0] * 40 + oid[1], &mut value);
    for component in &oid[2..] {
        push_oid_component(*component, &mut value);
    }

    if value.len() > 127 {
        return None;
    }

    let mut encoded = vec![0x06, value.len() as u8];
    encoded.extend(value);
    Some(encoded)
}

fn push_oid_component(mut component: u64, output: &mut Vec<u8>) {
    let mut encoded = vec![(component & 0x7f) as u8];
    component >>= 7;
    while component > 0 {
        encoded.push(((component & 0x7f) as u8) | 0x80);
        component >>= 7;
    }

    output.extend(encoded.into_iter().rev());
}

fn hash_payload(payload: &str) -> String {
    let digest = Sha256::digest(payload.as_bytes());
    hex::encode(digest)
}

fn log_value_hash(value: &str) -> String {
    hash_payload(value).chars().take(16).collect()
}

fn log_response_body_preview(value: &str) -> String {
    let escaped = value
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t");

    if escaped.len() <= 1_024 {
        return escaped;
    }

    let mut preview = escaped.chars().take(1_024).collect::<String>();
    preview.push_str("...[truncated]");
    preview
}

fn naive_datetime_from_millis(value: i64) -> Option<NaiveDateTime> {
    let seconds = value.div_euclid(1_000);
    let nanos = (value.rem_euclid(1_000) * 1_000_000) as u32;
    chrono::DateTime::<Utc>::from_timestamp(seconds, nanos).map(|value| value.naive_utc())
}

impl TryFrom<AppleTransactionPayload> for VerifiedAppleTransaction {
    type Error = AppleBillingError;

    fn try_from(value: AppleTransactionPayload) -> Result<Self, Self::Error> {
        let original_transaction_id = value
            .original_transaction_id
            .filter(|value| !value.trim().is_empty())
            .ok_or(AppleBillingError::InvalidPayload)?;
        let transaction_id = value
            .transaction_id
            .filter(|value| !value.trim().is_empty())
            .ok_or(AppleBillingError::InvalidPayload)?;
        let product_id = value
            .product_id
            .filter(|value| is_apple_premium_product_id(value))
            .ok_or(AppleBillingError::InvalidProduct)?;
        let environment = value
            .environment
            .as_deref()
            .and_then(normalize_apple_environment)
            .ok_or(AppleBillingError::InvalidEnvironment)?
            .to_string();
        let expires_at = value.expires_date.and_then(naive_datetime_from_millis);

        Ok(Self {
            original_transaction_id,
            transaction_id,
            product_id,
            environment,
            expires_at,
            is_revoked: value.revocation_date.is_some(),
        })
    }
}

impl TryFrom<AppleRenewalInfoPayload> for VerifiedAppleRenewalInfo {
    type Error = AppleBillingError;

    fn try_from(value: AppleRenewalInfoPayload) -> Result<Self, Self::Error> {
        let original_transaction_id = value
            .original_transaction_id
            .filter(|value| !value.trim().is_empty())
            .ok_or(AppleBillingError::InvalidPayload)?;
        let product_id = value
            .product_id
            .filter(|value| is_apple_premium_product_id(value));
        let environment = value
            .environment
            .as_deref()
            .and_then(normalize_apple_environment)
            .map(str::to_string);

        Ok(Self {
            original_transaction_id,
            product_id,
            environment,
            grace_period_expires_at: value
                .grace_period_expires_date
                .and_then(naive_datetime_from_millis),
            renewal_date: value.renewal_date.and_then(naive_datetime_from_millis),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ec_public_key_from_subject_public_key_info_extracts_uncompressed_p256_key() {
        let mut public_key = vec![0x04];
        public_key.extend(1_u8..=64);

        let mut subject_public_key_info = vec![
            0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06,
            0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
        ];
        subject_public_key_info.extend(public_key.clone());

        let extracted =
            ec_public_key_from_subject_public_key_info(subject_public_key_info.as_slice())
                .expect("valid P-256 SubjectPublicKeyInfo should decode");

        assert_eq!(extracted, public_key);
    }

    #[test]
    fn ec_public_key_from_subject_public_key_info_rejects_raw_spki_bytes_without_p256_prefix() {
        let public_key = vec![0x04; 65];

        let result = ec_public_key_from_subject_public_key_info(public_key.as_slice());

        assert!(result.is_err());
    }
}
