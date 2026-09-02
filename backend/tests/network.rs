use bochi_backend::network::{listen_address, ClientIpPolicy};
use std::net::{IpAddr, Ipv4Addr};

#[test]
fn server_listens_on_every_interface_by_default() {
    assert_eq!(listen_address(None, None), "0.0.0.0:8080");
}

#[test]
fn server_can_listen_only_on_the_configured_interface() {
    assert_eq!(
        listen_address(Some("100.64.0.1"), Some("8501")),
        "100.64.0.1:8501"
    );
}

#[test]
fn configured_client_allowlist_rejects_other_tailnet_devices() {
    let policy = ClientIpPolicy::from_csv(Some("100.64.0.1,100.64.0.2")).unwrap();

    assert!(policy.allows(IpAddr::V4(Ipv4Addr::new(100, 64, 0, 1))));
    assert!(policy.allows(IpAddr::V4(Ipv4Addr::new(100, 64, 0, 2))));
    assert!(!policy.allows(IpAddr::V4(Ipv4Addr::new(100, 64, 0, 3))));
}

#[test]
fn absent_client_allowlist_preserves_ci_and_production_access() {
    let policy = ClientIpPolicy::from_csv(None).unwrap();

    assert!(policy.allows(IpAddr::V4(Ipv4Addr::new(203, 0, 113, 10))));
}

#[test]
fn malformed_client_allowlist_fails_configuration() {
    assert!(ClientIpPolicy::from_csv(Some("100.64.0.1,not-an-ip")).is_err());
}
