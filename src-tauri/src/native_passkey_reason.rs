#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativePasskeyReason {
    AuthenticateGlobalPasskey,
    UnlockNote,
    SaveNote,
    UnlockProjectFolder,
    StoreWrappedKey,
    LoadWrappedKey,
    ClearWrappedKey,
}

impl NativePasskeyReason {
    pub fn from_input(input: Option<&str>) -> Self {
        let normalized = normalize_token(input);

        match normalized.as_str() {
            "unlock_note" | "unlock" | "decrypt_note" => Self::UnlockNote,
            "save_note" | "save" | "encrypt_note" => Self::SaveNote,
            "unlock_project_folder" | "unlock_folder" | "folder_unlock" => {
                Self::UnlockProjectFolder
            }
            "store_wrapped_key" | "store_key" => Self::StoreWrappedKey,
            "load_wrapped_key" | "load_key" => Self::LoadWrappedKey,
            "clear_wrapped_key" | "clear_key" | "delete_key" => Self::ClearWrappedKey,
            _ => Self::AuthenticateGlobalPasskey,
        }
    }

    pub fn code(self) -> &'static str {
        match self {
            Self::AuthenticateGlobalPasskey => "authenticate_global_passkey",
            Self::UnlockNote => "unlock_note",
            Self::SaveNote => "save_note",
            Self::UnlockProjectFolder => "unlock_project_folder",
            Self::StoreWrappedKey => "store_wrapped_key",
            Self::LoadWrappedKey => "load_wrapped_key",
            Self::ClearWrappedKey => "clear_wrapped_key",
        }
    }

    pub fn prompt(self) -> &'static str {
        match self {
            Self::AuthenticateGlobalPasskey => "Authenticate for Global Passkey",
            Self::UnlockNote => "Authenticate to unlock note",
            Self::SaveNote => "Authenticate to save note",
            Self::UnlockProjectFolder => "Authenticate to unlock project folder",
            Self::StoreWrappedKey => "Authenticate to store Global Passkey key material",
            Self::LoadWrappedKey => "Authenticate to load Global Passkey key material",
            Self::ClearWrappedKey => "Authenticate to clear Global Passkey key material",
        }
    }
}

fn normalize_token(input: Option<&str>) -> String {
    let raw = input.unwrap_or_default().trim().to_lowercase();

    if raw.is_empty() {
        return String::new();
    }

    raw.chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '_' })
        .collect::<String>()
        .split('_')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("_")
}
