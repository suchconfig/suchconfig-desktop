#[cfg(debug_assertions)]
pub const VAULT_KEYCHAIN_SERVICE: &str = "suchconfig.project_manager.dev";

#[cfg(not(debug_assertions))]
pub const VAULT_KEYCHAIN_SERVICE: &str = "suchconfig.project_manager";

#[cfg(debug_assertions)]
pub const VAULT_KEY_HOME_DIR: &str = ".suchconfig-dev";

#[cfg(not(debug_assertions))]
pub const VAULT_KEY_HOME_DIR: &str = ".suchconfig";
