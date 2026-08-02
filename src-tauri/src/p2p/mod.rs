pub mod commands;
mod device;
mod discovery;
mod frontiers;
mod iroh_sync;
mod iroh_transport;
mod pairing;
mod protocol;
mod qr;
mod settings;
mod store;
mod sync_manager;
mod transport;

use pairing::PairingState;
use sync_manager::SyncManager;

pub struct P2pAppState {
    pub pairing: PairingState,
    pub sync: SyncManager,
}

impl Default for P2pAppState {
    fn default() -> Self {
        Self {
            pairing: PairingState::default(),
            sync: SyncManager::default(),
        }
    }
}
