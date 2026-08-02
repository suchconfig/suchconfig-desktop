use serde::{Deserialize, Serialize};

use crate::error::VaultCoreError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ItemKind {
    EnvNote,
    GenericNote,
    PromptTemplate,
    Guideline,
    ApiSpec,
    SecurityPolicy,
    SecurityManifest,
    Password,
    ApiKey,
    SshKey,
    SecureNote,
}

impl ItemKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            ItemKind::EnvNote => "env_note",
            ItemKind::GenericNote => "generic_note",
            ItemKind::PromptTemplate => "prompt_template",
            ItemKind::Guideline => "guideline",
            ItemKind::ApiSpec => "api_spec",
            ItemKind::SecurityPolicy => "security_policy",
            ItemKind::SecurityManifest => "security_manifest",
            ItemKind::Password => "password",
            ItemKind::ApiKey => "api_key",
            ItemKind::SshKey => "ssh_key",
            ItemKind::SecureNote => "secure_note",
        }
    }

    pub fn from_str(value: &str) -> Result<Self, VaultCoreError> {
        match value {
            "env_note" => Ok(ItemKind::EnvNote),
            "generic_note" => Ok(ItemKind::GenericNote),
            "prompt_template" => Ok(ItemKind::PromptTemplate),
            "guideline" => Ok(ItemKind::Guideline),
            "api_spec" => Ok(ItemKind::ApiSpec),
            "security_policy" => Ok(ItemKind::SecurityPolicy),
            "security_manifest" => Ok(ItemKind::SecurityManifest),
            "password" => Ok(ItemKind::Password),
            "api_key" => Ok(ItemKind::ApiKey),
            "ssh_key" => Ok(ItemKind::SshKey),
            "secure_note" => Ok(ItemKind::SecureNote),
            other => Err(VaultCoreError::UnknownKind(other.to_string())),
        }
    }

    pub fn all() -> &'static [ItemKind] {
        &[
            ItemKind::EnvNote,
            ItemKind::GenericNote,
            ItemKind::PromptTemplate,
            ItemKind::Guideline,
            ItemKind::ApiSpec,
            ItemKind::SecurityPolicy,
            ItemKind::SecurityManifest,
            ItemKind::Password,
            ItemKind::ApiKey,
            ItemKind::SshKey,
            ItemKind::SecureNote,
        ]
    }
}
