// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `pnpm add some-package --dir phoenix-app/assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html';
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';
import topbar from '../vendor/topbar.cjs';
import { MarkdownWorkspace } from './markdown_workspace.js';

let colocatedHooks = {};
try {
  const colocatedModule = require('phoenix-colocated/suchconfig_desktop');
  colocatedHooks = colocatedModule.hooks || {};
} catch (e) {
  console.warn('Colocated hooks not available:', e);
}

const ResizableSplit = {
  mounted() {
    this.storageKey = this.el.dataset.storageKey || 'sc:split';
    this.defaultPct = parseFloat(this.el.dataset.defaultPct) || 33.33;
    this.min = parseFloat(this.el.dataset.min) || 22;
    this.max = parseFloat(this.el.dataset.max) || 70;
    this.leftPct = this.readStoredPct();
    this.dragging = false;
    this.resizer = this.el.querySelector('[data-resizer]');

    this.applyLeftPct(this.leftPct);

    if (this.resizer) {
      this.onMouseDown = (e) => this.startDrag(e);
      this.onDoubleClick = () => this.reset();
      this.onKeyDown = (e) => this.onResizerKey(e);
      this.resizer.addEventListener('mousedown', this.onMouseDown);
      this.resizer.addEventListener('dblclick', this.onDoubleClick);
      this.resizer.addEventListener('keydown', this.onKeyDown);
    }
  },

  destroyed() {
    this.stopDrag();
    if (this.resizer) {
      if (this.onMouseDown) {
        this.resizer.removeEventListener('mousedown', this.onMouseDown);
      }
      if (this.onDoubleClick) {
        this.resizer.removeEventListener('dblclick', this.onDoubleClick);
      }
      if (this.onKeyDown) {
        this.resizer.removeEventListener('keydown', this.onKeyDown);
      }
    }
  },

  readStoredPct() {
    try {
      const v = parseFloat(localStorage.getItem(this.storageKey));
      if (Number.isFinite(v) && v >= this.min && v <= this.max) {
        return v;
      }
    } catch (_e) {}
    return this.defaultPct;
  },

  persistPct() {
    try {
      localStorage.setItem(this.storageKey, String(this.leftPct));
    } catch (_e) {}
  },

  applyLeftPct(pct) {
    this.leftPct = pct;
    this.el.style.setProperty('--pv-left', `${pct}%`);
    this.persistPct();
  },

  setDragging(active) {
    this.dragging = active;
    this.el.classList.toggle('dragging', active);
  },

  startDrag(e) {
    e.preventDefault();
    this.setDragging(true);

    this.onMove = (ev) => {
      const rect = this.el.getBoundingClientRect();
      if (!rect || !rect.width) {
        return;
      }
      const pct = ((ev.clientX - rect.left) / rect.width) * 100;
      this.applyLeftPct(Math.max(this.min, Math.min(this.max, pct)));
    };

    this.onUp = () => this.stopDrag();

    document.addEventListener('mousemove', this.onMove);
    document.addEventListener('mouseup', this.onUp);
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  },

  stopDrag() {
    if (!this.dragging && !this.onMove && !this.onUp) {
      return;
    }
    this.setDragging(false);
    if (this.onMove) {
      document.removeEventListener('mousemove', this.onMove);
      this.onMove = null;
    }
    if (this.onUp) {
      document.removeEventListener('mouseup', this.onUp);
      this.onUp = null;
    }
    document.body.style.cursor = '';
    document.body.style.userSelect = '';
  },

  onResizerKey(e) {
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      this.applyLeftPct(Math.max(this.min, this.leftPct - 2));
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      this.applyLeftPct(Math.min(this.max, this.leftPct + 2));
    } else if (e.key === 'Home') {
      e.preventDefault();
      this.reset();
    }
  },

  reset() {
    this.applyLeftPct(this.defaultPct);
  },
};

const ToastAutoDismiss = {
  mounted() {
    const ms = parseInt(this.el.dataset.autocloseMs || '10000', 10);
    this.timer = setTimeout(() => {
      this.timer = null;
      if (this.el && this.el.isConnected) {
        this.el.click();
      }
    }, Number.isFinite(ms) ? ms : 10000);
  },

  destroyed() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  },
};

const CopyPathHook = {
  mounted() {
    this.defaultLabel = (this.el.textContent || '').trim() || 'Copy path';
    this.copiedLabelTimeout = null;

    this.handleClick = async (e) => {
      const raw = this.el.dataset.copyPath;
      const path = raw != null ? String(raw) : '';
      if (!path) {
        return;
      }
      e.preventDefault();
      e.stopPropagation();
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          await navigator.clipboard.writeText(path);
        } else {
          const textArea = document.createElement('textarea');
          textArea.value = path;
          textArea.style.position = 'fixed';
          textArea.style.top = '0';
          textArea.style.left = '0';
          textArea.style.opacity = '0';
          textArea.style.pointerEvents = 'none';
          document.body.appendChild(textArea);
          textArea.focus();
          textArea.select();
          const ok = document.execCommand('copy');
          document.body.removeChild(textArea);
          if (!ok) {
            throw new Error('execCommand copy failed');
          }
        }
        if (this.copiedLabelTimeout) {
          clearTimeout(this.copiedLabelTimeout);
        }
        this.el.textContent = 'Copied';
        this.copiedLabelTimeout = setTimeout(() => {
          this.copiedLabelTimeout = null;
          if (this.el) {
            this.el.textContent = this.defaultLabel;
          }
        }, 2000);
        this.pushEvent('clipboard_copy_done', { ok: true });
      } catch (_e) {
        this.pushEvent('clipboard_copy_done', { ok: false });
      }
    };
    this.el.addEventListener('click', this.handleClick);
  },

  destroyed() {
    if (this.copiedLabelTimeout) {
      clearTimeout(this.copiedLabelTimeout);
    }
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },
};

const TextareaValueHook = {
  mounted() {
    this.applyValue();
  },
  updated() {
    this.applyValue();
  },
  applyValue() {
    const v = this.el && this.el.dataset ? this.el.dataset.value : null;
    if (v == null) {
      return;
    }
    const next = String(v);
    if (this.el.value !== next) {
      this.el.value = next;
    }
  },
};

const TagPicker = {
  mounted() {
    this.menu = this.el.querySelector('[data-tag-picker-menu]');
    this.trigger = this.el.querySelector('[data-tag-picker-trigger]');

    this.onDocClick = () => this.close();

    this.onTriggerClick = (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.toggle();
    };

    this.trigger?.addEventListener('click', this.onTriggerClick);
    document.addEventListener('click', this.onDocClick);
  },

  updated() {
    this.trigger?.removeEventListener('click', this.onTriggerClick);
    this.trigger = this.el.querySelector('[data-tag-picker-trigger]');
    this.menu = this.el.querySelector('[data-tag-picker-menu]');
    this.trigger?.addEventListener('click', this.onTriggerClick);
  },

  destroyed() {
    this.trigger?.removeEventListener('click', this.onTriggerClick);
    document.removeEventListener('click', this.onDocClick);
  },

  toggle() {
    const open = this.el.classList.toggle('is-open');
    this.trigger?.setAttribute('aria-expanded', open ? 'true' : 'false');
  },

  close() {
    this.el.classList.remove('is-open');
    this.trigger?.setAttribute('aria-expanded', 'false');
  },
};

const NEW_ENTRY_KIND_BY_TYPE = {
  login: 'password',
  api: 'api_key',
  ssh: 'ssh_key',
  note: 'secure_note',
};

const NEW_ENTRY_TITLE_PLACEHOLDER = {
  login: 'e.g. GitHub — work',
  api: 'e.g. OpenAI — prod',
  ssh: 'e.g. deploy-bot · prod-edge',
  note: 'e.g. Recovery codes — Stripe',
};

const NewEntryTypePicker = {
  mounted() {
    this.onClick = (event) => {
      const card = event.target.closest('.type-card');
      if (!card || !this.el.contains(card)) {
        return;
      }
      const type = card.getAttribute('phx-value-type');
      if (type) {
        this.applyType(type);
      }
    };
    this.el.addEventListener('click', this.onClick);
  },

  updated() {
    const active = this.el.querySelector('.type-card.active');
    const type = active && active.getAttribute('phx-value-type');
    if (type) {
      this.applyType(type, false);
    }
  },

  destroyed() {
    this.el.removeEventListener('click', this.onClick);
  },

  applyType(type, scrollIntoView = true) {
    this.el.querySelectorAll('.type-card').forEach((card) => {
      card.classList.toggle('active', card.getAttribute('phx-value-type') === type);
    });

    const kindInput = this.el.querySelector('input[name="kind"]');
    if (kindInput && NEW_ENTRY_KIND_BY_TYPE[type]) {
      kindInput.value = NEW_ENTRY_KIND_BY_TYPE[type];
    }

    const titleInput = this.el.querySelector('#new-entry-title-input');
    if (titleInput && NEW_ENTRY_TITLE_PLACEHOLDER[type]) {
      titleInput.placeholder = NEW_ENTRY_TITLE_PLACEHOLDER[type];
    }

    if (scrollIntoView) {
      const panel = this.el.querySelector(`.entry-type-panel[data-entry-type="${type}"]`);
      panel?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
    }
  },
};

const CopyButton = {
  mounted() {
    this.handleEvent('copy_to_clipboard', ({ content }) => {
      if (content != null) {
        this.copyToClipboard(content);
      }
    });

    this.handleClick = (e) => {
      const text = this.copyText();
      if (!text) {
        return;
      }

      e.preventDefault();
      e.stopPropagation();

      const eventName = this.el.dataset.copyEvent || 'copy_to_clipboard';
      const eventPayload = this.el.dataset.copyPayload
        ? JSON.parse(this.el.dataset.copyPayload)
        : {};

      this.copyToClipboard(text)
        .then(() => {
          this.pushEvent(eventName, eventPayload);
        })
        .catch(() => {
          this.pushEvent(eventName, { ...eventPayload, error: 'Copy failed' });
        });
    };

    this.el.addEventListener('click', this.handleClick);
  },

  copyText() {
    const targetId = this.el.dataset.copyTarget;
    if (targetId) {
      const node = document.getElementById(targetId);
      if (node) {
        return (node.value ?? node.textContent ?? '').trim();
      }
    }

    const inline = this.el.dataset.copyText;
    return inline ? inline.trim() : '';
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },

  async copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      try {
        await navigator.clipboard.writeText(text);
        return;
      } catch (err) {}
    }

    return this.fallbackCopyTextToClipboard(text);
  },

  fallbackCopyTextToClipboard(text) {
    return new Promise((resolve, reject) => {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.top = '0';
      textArea.style.left = '0';
      textArea.style.opacity = '0';
      textArea.style.pointerEvents = 'none';
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();

      try {
        const successful = document.execCommand('copy');
        document.body.removeChild(textArea);
        if (successful) {
          resolve();
        } else {
          reject(new Error('execCommand copy failed'));
        }
      } catch (err) {
        document.body.removeChild(textArea);
        reject(err);
      }
    });
  },
};

const VAULT_KEY_ID_DEFAULT = 'suchconfig.project_manager.vault';

const vaultSkippedCookieName = () =>
  document.querySelector('meta[name="suchconfig-vault-skipped-cookie"]')?.content ||
  'suchconfig_vault_skipped';

const VaultKeyStore = {
  mounted() {
    this.handleEvent('set_vault_skipped_cookie', () => {
      document.cookie = `${vaultSkippedCookieName()}=1; path=/; max-age=3600`;
    });
    this.handleEvent('clear_vault_skipped_cookie', () => {
      document.cookie = `${vaultSkippedCookieName()}=; path=/; max-age=0`;
    });
    this.handleEvent('store_vault_key', (payload) => {
      const { key_id, wrapped_key } = payload || {};
      if (!key_id || wrapped_key == null) return;
      if (window.SuchConfigNativePasskey) {
        window.SuchConfigNativePasskey
          .storeWrappedKey(key_id, wrapped_key)
          .then((result) => {
            if (!result || (result.stored !== true && result.ok !== true)) {
              this.pushEvent('vault_key_stored', {
                ok: false,
                message: result && result.message ? result.message : 'Store reported failure',
              });
              return;
            }
            return window.SuchConfigNativePasskey.loadWrappedKey(key_id).then((loadResult) => {
              const storedOk =
                loadResult &&
                loadResult.found &&
                loadResult.wrapped_key &&
                String(loadResult.wrapped_key) === String(wrapped_key);
              this.pushEvent('vault_key_stored', {
                ok: storedOk,
                message: storedOk
                  ? (result && result.message) || ''
                  : 'Key could not be read back from Keychain. It may not have been saved.',
              });
            });
          })
          .catch((err) => {
            this.pushEvent('vault_key_stored', {
              ok: false,
              message: err && err.message ? err.message : 'Store failed',
            });
          });
      } else {
        this.pushEvent('vault_key_stored', { ok: false, message: 'Native bridge not available' });
      }
    });
  },
};

const GlobalPasskeyNative = {
  mounted() {
    this.handleEvent('run_native_global_passkey_auth', () => {
      this.runNativeAuth();
    });
    this.handleEvent('vault_key_from_db', (payload) => {
      this.applyVaultKeyFromDb(payload);
    });
    this.bindUnlockTriggers();
    this.reportAvailability();
  },

  updated() {
    this.bindUnlockTriggers();
  },

  destroyed() {
    this.unbindUnlockTriggers();
  },

  bindUnlockTriggers() {
    if (this.unlockForm && !this.unlockFormSubmitBound) {
      this.unlockFormSubmitBound = (e) => {
        e.preventDefault();
        this.runNativeAuth();
      };
      this.unlockForm.addEventListener('submit', this.unlockFormSubmitBound, true);
    }
    if (!this.unlockClickBound) {
      this.unlockClickBound = (e) => {
        const btn = e.target.closest('#native-global-passkey-auth-btn');
        if (!btn || btn.disabled) return;
        e.preventDefault();
        this.runNativeAuth();
      };
      document.addEventListener('click', this.unlockClickBound, true);
    }
  },

  unbindUnlockTriggers() {
    if (this.unlockForm && this.unlockFormSubmitBound) {
      this.unlockForm.removeEventListener('submit', this.unlockFormSubmitBound, true);
      this.unlockFormSubmitBound = null;
    }
    if (this.unlockClickBound) {
      document.removeEventListener('click', this.unlockClickBound, true);
      this.unlockClickBound = null;
    }
  },

  get unlockForm() {
    return document.getElementById('app-unlock-form');
  },

  reportAvailability() {
    if (window.SuchConfigNativePasskey) {
      window.SuchConfigNativePasskey
        .available()
        .then((availability) => {
          this.pushEvent('native_global_passkey_available', availability || {});
        })
        .catch(() => {
          this.pushEvent('native_global_passkey_available', {
            supported: false,
            platform: 'unknown',
            provider: 'error',
          });
        });
    } else {
      this.pushEvent('native_global_passkey_available', {
        supported: false,
        platform: 'browser',
        provider: 'no_bridge',
      });
    }
  },

  applyVaultKeyFromDb(payload) {
    if (payload && payload.key) {
      this.pushEvent('native_global_passkey_authenticated', {
        passkey: payload.key,
        unwrapped_key: payload.key,
      });
    } else {
      this.pushEvent('native_global_passkey_authenticated', {
        first_time: true,
      });
    }
  },

  passkeyContext() {
    const unlockEl = document.getElementById('app-unlock-modal');
    const reason =
      unlockEl?.dataset?.nativePasskeyReason ||
      this.el.dataset.nativePasskeyReason ||
      'Unlock your vault.';
    const vaultKeyId =
      unlockEl?.dataset?.vaultKeyId ||
      this.el.dataset.vaultKeyId ||
      VAULT_KEY_ID_DEFAULT;
    return { reason, vaultKeyId };
  },

  async runNativeAuth() {
    const { reason, vaultKeyId } = this.passkeyContext();
    this.pushEvent('confirm_global_passkey', {});

    if (!window.SuchConfigNativePasskey) {
      this.pushEvent('native_global_passkey_auth_failed', {
        message: 'Native passkey bridge is not available.',
      });
      return;
    }

    try {
      const result = await window.SuchConfigNativePasskey.authenticate(reason);
      if (result && (result.authenticated || result.ok)) {
        const loadResult = await window.SuchConfigNativePasskey.loadWrappedKey(vaultKeyId);
        if (loadResult && loadResult.found && loadResult.wrapped_key) {
          this.pushEvent('native_global_passkey_authenticated', {
            ...result,
            passkey: loadResult.wrapped_key,
            unwrapped_key: loadResult.wrapped_key,
          });
        } else {
          this.pushEvent('vault_key_not_found', {});
        }
      } else {
        this.pushEvent('native_global_passkey_auth_failed', result || {});
      }
    } catch (err) {
      this.pushEvent('native_global_passkey_auth_failed', {
        message: err.message || 'Native authentication request failed.',
      });
    }
  },
};

const LinkedProjectSync = {
  mounted() {
    this.setupListener();
    this.syncWatch();
  },
  updated() {
    this.syncWatch();
  },
  destroyed() {
    if (this.unlisten) {
      this.unlisten();
    }
  },
  async setupListener() {
    if (!window.__TAURI__?.event?.listen) {
      return;
    }
    const { listen } = window.__TAURI__.event;
    this.unlisten = await listen('linked_file_changed', (event) => {
      const payload = event.payload || {};
      this.pushEvent('linked_file_changed', payload);
    });
  },
  async syncWatch() {
    const folderId = this.el.dataset.linkedFolderId;
    const root = this.el.dataset.linkedRootPath;
    if (!window.__TAURI__?.core?.invoke || !folderId || !root) {
      return;
    }
    const { invoke } = window.__TAURI__.core;
    try {
      await invoke('watch_linked_project', {
        folder_id: parseInt(folderId, 10),
        root,
      });
    } catch (err) {
      console.warn('watch_linked_project failed:', err);
    }
  },
};

const FolderPicker = {
  mounted() {
    this.handleClick = async (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (window.__TAURI__) {
        try {
          const { invoke } = window.__TAURI__.core;
          const path = await invoke('select_project_folder');
          if (path) {
            this.pushEvent('folder_selected', { path });
          }
        } catch (err) {
          console.error('Failed to select folder:', err);
          this.pushEvent('folder_select_error', {
            error: err.message || 'Failed to open folder picker',
          });
        }
      } else {
        console.warn('Tauri API not available - running in browser mode');
        this.pushEvent('folder_select_error', {
          error: 'Folder selection requires the desktop app',
        });
      }
    };

    this.el.addEventListener('click', this.handleClick);
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },
};

const DropZone = {
  async mounted() {
    this.unlisten = null;

    this.handleDragOver = (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.el.classList.add('border-blue-500', 'bg-blue-50');
    };

    this.handleDragLeave = (e) => {
      e.preventDefault();
      e.stopPropagation();
      this.el.classList.remove('border-blue-500', 'bg-blue-50');
    };

    this.handleClick = async (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (window.__TAURI__) {
        try {
          const { invoke } = window.__TAURI__.core;
          const path = await invoke('select_project_folder');
          if (path) {
            this.pushEvent('folder_selected', { path });
          }
        } catch (err) {
          console.error('Failed to select folder:', err);
          this.pushEvent('folder_select_error', {
            error: err.message || 'Failed to open folder picker',
          });
        }
      } else {
        this.pushEvent('folder_select_error', {
          error: 'Folder selection requires the desktop app',
        });
      }
    };

    this.el.addEventListener('dragover', this.handleDragOver);
    this.el.addEventListener('dragleave', this.handleDragLeave);
    this.el.addEventListener('click', this.handleClick);

    if (window.__TAURI__) {
      console.log(
        'Tauri detected, available APIs:',
        Object.keys(window.__TAURI__)
      );

      try {
        const { listen } = window.__TAURI__.event;

        const handleDrop = async (eventName, event) => {
          console.log(`${eventName} received:`, JSON.stringify(event, null, 2));
          let paths = event.payload;
          if (event.payload && event.payload.paths) {
            paths = event.payload.paths;
          }
          if (paths && Array.isArray(paths) && paths.length > 0) {
            const path = paths[0];
            console.log('DropZone: Dropped path:', path);
            this.el.classList.remove('border-blue-500', 'bg-blue-50');

            const ext = path.split('.').pop()?.toLowerCase();
            if (['csv', 'tsv', 'txt', 'json', 'xml'].includes(ext)) {
              console.log(
                'DropZone: Ignoring file drop (not a directory):',
                path
              );
              return;
            }

            this.pushEvent('folder_selected', { path });
          }
        };

        const handleHover = (eventName, event) => {
          console.log(`${eventName} received:`, event);
          this.el.classList.add('border-blue-500', 'bg-blue-50');
        };

        const handleLeave = (eventName, event) => {
          console.log(`${eventName} received`);
          this.el.classList.remove('border-blue-500', 'bg-blue-50');
        };

        // Listen for custom events emitted from Rust (our handlers)
        // AND the tauri:// prefixed events (just in case)
        const dropEvents = [
          'file-drop', // Our custom event from Rust
          'tauri://file-drop',
          'tauri://drag-drop',
        ];
        const hoverEvents = [
          'file-drop-hover', // Our custom event from Rust
          'tauri://file-drop-hover',
          'tauri://drag-over',
        ];
        const leaveEvents = [
          'file-drop-cancelled', // Our custom event from Rust
          'tauri://file-drop-cancelled',
          'tauri://drag-leave',
        ];

        this.unlisteners = [];

        for (const eventName of dropEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleDrop(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        for (const eventName of hoverEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleHover(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        for (const eventName of leaveEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleLeave(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        console.log('Tauri file-drop listeners registered for:', [
          ...dropEvents,
          ...hoverEvents,
          ...leaveEvents,
        ]);
      } catch (err) {
        console.warn('Failed to setup Tauri drag-drop listener:', err);
      }
    }
  },

  destroyed() {
    if (this.handleDragOver) {
      this.el.removeEventListener('dragover', this.handleDragOver);
    }
    if (this.handleDragLeave) {
      this.el.removeEventListener('dragleave', this.handleDragLeave);
    }
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
    if (this.unlisteners) {
      this.unlisteners.forEach((unlisten) => unlisten());
    }
  },
};

const ProjectFileReader = {
  mounted() {
    this.el.addEventListener('phx:read_project_files', async (e) => {
      const { path } = e.detail;

      if (window.__TAURI__) {
        try {
          const { invoke } = window.__TAURI__.core;
          const files = await invoke('read_project_files', { path });
          this.pushEvent('project_files_read', { path, files });
        } catch (err) {
          console.error('Failed to read project files:', err);
          this.pushEvent('project_files_error', {
            error: err.message || 'Failed to read project files',
          });
        }
      } else {
        this.pushEvent('project_files_error', {
          error: 'File reading requires the desktop app',
        });
      }
    });
  },
};

const CsvDropZone = {
  async mounted() {
    this.isDragging = false;

    this.handleClick = async (e) => {
      if (e.target.tagName === 'INPUT') return;

      e.preventDefault();
      e.stopPropagation();

      if (window.__TAURI__) {
        try {
          const { invoke } = window.__TAURI__.core;
          const result = await invoke('select_csv_file');

          if (result) {
            this.pushEvent('tauri_file_dropped', {
              filename: result.filename,
              size: result.size,
              content: result.content,
              path: result.path,
            });
          }
        } catch (err) {
          console.error('CsvDropZone: Failed to select file:', err);
          this.pushEvent('tauri_file_error', {
            error: err.message || 'Failed to open file picker',
          });
        }
      }
    };

    this.el.addEventListener('click', this.handleClick);

    if (window.__TAURI__) {
      try {
        const { listen } = window.__TAURI__.event;
        const { invoke } = window.__TAURI__.core;

        this.unlisteners = [];

        const handleDrop = async (eventName, event) => {
          console.log('CsvDropZone: File drop received:', event);
          this.el.classList.remove('border-blue-400', 'bg-blue-50');
          this.isDragging = false;

          let paths = event.payload;
          if (event.payload && event.payload.paths) {
            paths = event.payload.paths;
          }

          if (paths && paths.length > 0) {
            const filePath = paths[0];
            const ext = filePath.split('.').pop()?.toLowerCase();

            if (['csv', 'tsv', 'txt'].includes(ext)) {
              try {
                const fileData = await invoke('read_file_content', {
                  path: filePath,
                });
                this.pushEvent('tauri_file_dropped', {
                  filename: fileData.filename,
                  size: fileData.size,
                  content: fileData.content,
                  path: fileData.path,
                });
              } catch (err) {
                console.error('Failed to read dropped file:', err);
                this.pushEvent('tauri_file_error', {
                  error: err.message || 'Failed to read file',
                });
              }
            } else {
              this.pushEvent('tauri_file_error', {
                error:
                  'Invalid file type. Please drop a .csv, .tsv, or .txt file.',
              });
            }
          }
        };

        const handleHover = (eventName, event) => {
          if (!this.isDragging) {
            this.isDragging = true;
            this.el.classList.add('border-blue-400', 'bg-blue-50');
          }
        };

        const handleLeave = (eventName, event) => {
          this.isDragging = false;
          this.el.classList.remove('border-blue-400', 'bg-blue-50');
        };

        const dropEvents = ['file-drop', 'tauri://file-drop'];
        const hoverEvents = ['file-drop-hover', 'tauri://file-drop-hover'];
        const leaveEvents = [
          'file-drop-cancelled',
          'tauri://file-drop-cancelled',
        ];

        for (const eventName of dropEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleDrop(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        for (const eventName of hoverEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleHover(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        for (const eventName of leaveEvents) {
          const unlisten = await listen(eventName, (e) =>
            handleLeave(eventName, e)
          );
          this.unlisteners.push(unlisten);
        }

        console.log('CsvDropZone: Tauri file-drop listeners registered');
      } catch (err) {
        console.warn('CsvDropZone: Failed to setup Tauri listeners:', err);
      }
    }
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
    if (this.unlisteners) {
      this.unlisteners.forEach((unlisten) => unlisten());
    }
  },
};

const ParsingProgress = {
  mounted() {
    this.progressBar = this.el.querySelector('.progress-bar-fill');
    this.messageEl = document.getElementById('parsing-status-message');
    this.phaseIcons = {
      parsing: document.getElementById('phase-parsing'),
      schema: document.getElementById('phase-schema'),
      analyzing: document.getElementById('phase-analyzing'),
    };

    this.fileSize = parseInt(this.el.dataset.fileSize || '0', 10);
    this.currentProgress = 0;
    this.phaseStartProgress = 0;
    this.phaseTargetProgress = 55;
    this.phaseStartTime = Date.now();
    this.phaseDuration = this.estimateParseTime(this.fileSize);
    this.totalLines = 0;
    this.isComplete = false;

    this.handleEvent('parsing_progress', (data) => {
      const { phase, progress, message, total_lines, row_count } = data;

      if (total_lines) {
        this.totalLines = total_lines;
        this.phaseDuration = this.estimateDurationFromLines(total_lines);
      }

      if (this.messageEl) {
        this.messageEl.textContent = message;
      }

      this.updatePhaseIcons(phase);

      if (phase === 'parsing') {
        this.phaseStartProgress = 5;
        this.phaseTargetProgress = 55;
        this.phaseStartTime = Date.now();
      } else if (phase === 'schema') {
        this.currentProgress = 60;
        this.phaseStartProgress = 60;
        this.phaseTargetProgress = 80;
        this.phaseStartTime = Date.now();
        this.phaseDuration = this.estimateAnalysisTime(
          row_count || this.totalLines
        );
      } else if (phase === 'analyzing') {
        this.currentProgress = 85;
        this.phaseStartProgress = 85;
        this.phaseTargetProgress = 98;
        this.phaseStartTime = Date.now();
        this.phaseDuration = 1000;
      } else if (phase === 'complete') {
        this.isComplete = true;
        this.currentProgress = 100;
        this.setProgress(100);
      }
    });

    this.startAnimation();
  },

  updatePhaseIcons(currentPhase) {
    const phases = ['parsing', 'schema', 'analyzing'];
    const phaseMap = { parsing: 0, schema: 1, analyzing: 2, complete: 3 };
    const currentIndex = phaseMap[currentPhase] ?? -1;

    phases.forEach((phase, index) => {
      const icon = this.phaseIcons[phase];
      if (!icon) return;

      icon.classList.remove(
        'text-gray-400',
        'text-blue-500',
        'text-green-500',
        'animate-pulse'
      );

      if (currentPhase === 'complete' || index < currentIndex) {
        icon.classList.add('text-green-500');
      } else if (index === currentIndex) {
        icon.classList.add('text-blue-500', 'animate-pulse');
      } else {
        icon.classList.add('text-gray-400');
      }
    });
  },

  estimateParseTime(bytes) {
    const mb = bytes / (1024 * 1024);
    if (mb < 1) return 3000;
    if (mb < 5) return 8000;
    if (mb < 10) return 15000;
    if (mb < 20) return 30000;
    if (mb < 50) return 60000;
    return Math.min(mb * 2000, 180000);
  },

  estimateDurationFromLines(lines) {
    if (lines < 1000) return 2000;
    if (lines < 10000) return 5000;
    if (lines < 50000) return 15000;
    if (lines < 100000) return 30000;
    if (lines < 500000) return 60000;
    return Math.min(lines * 0.5, 180000);
  },

  estimateAnalysisTime(rowCount) {
    if (!rowCount || rowCount < 1000) return 2000;
    if (rowCount < 10000) return 5000;
    if (rowCount < 50000) return 10000;
    if (rowCount < 100000) return 20000;
    return Math.min(rowCount * 0.3, 60000);
  },

  startAnimation() {
    if (!this.progressBar) return;

    const animate = () => {
      if (this.isComplete) {
        this.setProgress(100);
        return;
      }

      const elapsed = Date.now() - this.phaseStartTime;
      const phaseProgress = Math.min(elapsed / this.phaseDuration, 0.95);
      const easedProgress = this.easeOutCubic(phaseProgress);

      const range = this.phaseTargetProgress - this.phaseStartProgress;
      const targetInPhase = this.phaseStartProgress + range * easedProgress;

      this.currentProgress = Math.max(this.currentProgress, targetInPhase);
      this.setProgress(Math.min(this.currentProgress, 98));

      this.animationFrame = requestAnimationFrame(animate);
    };

    this.animationFrame = requestAnimationFrame(animate);
  },

  setProgress(value) {
    if (this.progressBar) {
      this.progressBar.style.width = `${value}%`;
    }
  },

  easeOutCubic(x) {
    return 1 - Math.pow(1 - x, 3);
  },

  destroyed() {
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
    }
  },
};

const P2pPairingSync = {
  mounted() {
    this.unlisteners = [];
    const invoke = window.__TAURI__?.core?.invoke;
    const eventApi = window.__TAURI__?.event;
    const push = (event, payload) => {
      this.pushEvent(event, payload || {});
    };

    const listenTauri = (name, handler) => {
      if (!eventApi?.listen) return;
      eventApi
        .listen(name, handler)
        .then((unlisten) => {
          this.unlisteners.push(unlisten);
        })
        .catch((err) => {
          console.error(`${name} listener failed:`, err);
        });
    };

    const fail = (message) => {
      push('p2p_failed', { message: message || 'Pairing failed.' });
    };

    this.handleEvent('fetch_p2p_status', async () => {
      if (!invoke) return;
      try {
        const localDevice = await invoke('p2p_get_local_device');
        const peerPayload = await invoke('p2p_list_peers');
        const peers = peerPayload?.peers || peerPayload?.['peers'] || [];
        push('p2p_status', { local_device: localDevice, peers });
      } catch (err) {
        console.error('fetch_p2p_status failed:', err);
      }
    });

    this.handleEvent('p2p_start_pairing_host', async () => {
      if (!invoke) {
        fail('Device pairing requires the desktop app.');
        return;
      }
      try {
        const result = await invoke('p2p_start_pairing');
        push('p2p_host_started', result);
      } catch (err) {
        fail(err?.message || String(err));
      }
    });

    this.handleEvent('p2p_submit_pairing_offer', async (payload) => {
      if (!invoke) {
        fail('Device pairing requires the desktop app.');
        return;
      }
      const offerJson = payload.offer_json || payload['offer_json'] || '';
      try {
        const result = await invoke('p2p_submit_pairing_offer', { offerJson });
        push('p2p_offer_submitted', result);
      } catch (err) {
        fail(err?.message || String(err));
      }
    });

    this.handleEvent('p2p_confirm_pairing_responder', async (payload) => {
      if (!invoke) {
        fail('Device pairing requires the desktop app.');
        return;
      }
      const sessionId = payload.session_id || payload['session_id'] || '';
      try {
        const result = await invoke('p2p_confirm_pairing_responder', {
          sessionId,
        });
        push('p2p_responder_confirmed', result);
      } catch (err) {
        fail(err?.message || String(err));
      }
    });

    this.handleEvent('p2p_complete_pairing_initiator', async (payload) => {
      if (!invoke) {
        fail('Device pairing requires the desktop app.');
        return;
      }
      const responseJson =
        payload.response_json || payload['response_json'] || '';
      try {
        const result = await invoke('p2p_complete_pairing_initiator', {
          responseJson,
        });
        push('p2p_initiator_completed', result);
      } catch (err) {
        fail(err?.message || String(err));
      }
    });

    this.handleEvent('p2p_cancel_pairing', async (payload) => {
      if (!invoke) return;
      const sessionId = payload.session_id || payload['session_id'] || '';
      if (!sessionId) return;
      try {
        await invoke('p2p_cancel_pairing', { sessionId });
      } catch (err) {
        console.error('p2p_cancel_pairing failed:', err);
      }
    });

    this.handleEvent('p2p_remove_peer', async (payload) => {
      if (!invoke) {
        fail('Device pairing requires the desktop app.');
        return;
      }
      const deviceId = payload.device_id || payload['device_id'] || '';
      try {
        await invoke('p2p_remove_peer', { deviceId });
        push('p2p_peer_removed', { device_id: deviceId });
      } catch (err) {
        fail(err?.message || String(err));
      }
    });

    if (invoke) {
      invoke('p2p_get_local_device')
        .then((localDevice) =>
          invoke('p2p_list_peers').then((peerPayload) => {
            const peers = peerPayload?.peers || peerPayload?.['peers'] || [];
            push('p2p_status', { local_device: localDevice, peers });
          })
        )
        .catch((err) => console.error('initial p2p status failed:', err));

      invoke('p2p_get_lan_sync_status')
        .then((status) => push('p2p_lan_status', status))
        .catch((err) => console.error('initial p2p lan status failed:', err));
    }

    this.handleEvent('fetch_p2p_lan_status', async () => {
      if (!invoke) return;
      try {
        const status = await invoke('p2p_get_lan_sync_status');
        push('p2p_lan_status', status);
      } catch (err) {
        console.error('fetch_p2p_lan_status failed:', err);
      }
    });

    this.handleEvent('p2p_set_lan_sync_enabled', async (payload) => {
      if (!invoke) {
        push('p2p_lan_sync_error', { message: 'LAN sync requires the desktop app.' });
        return;
      }
      const enabled = payload.enabled ?? payload['enabled'] ?? false;
      try {
        const status = await invoke('p2p_set_lan_sync_enabled', { enabled });
        push('p2p_lan_status', status);
      } catch (err) {
        push('p2p_lan_sync_error', { message: err?.message || String(err) });
      }
    });

    this.handleEvent('p2p_connect_handoff', async (payload) => {
      if (!invoke) {
        push('p2p_lan_sync_error', { message: 'LAN handoff requires the desktop app.' });
        return;
      }
      const deviceId = payload.device_id || payload['device_id'] || '';
      try {
        await invoke('p2p_connect_handoff', { deviceId });
        push('p2p_handoff_ready_for_bundles', { device_id: deviceId });
      } catch (err) {
        push('p2p_lan_sync_error', { message: err?.message || String(err) });
      }
    });

    this.handleEvent('p2p_send_handoff_bundles', async (payload) => {
      if (!invoke) {
        push('p2p_lan_sync_error', { message: 'LAN handoff requires the desktop app.' });
        return;
      }
      const bundles = payload.bundles || payload['bundles'] || [];
      try {
        await invoke('p2p_send_handoff_bundles', { bundles });
        push('p2p_lan_handoff_complete', {});
      } catch (err) {
        push('p2p_lan_sync_error', { message: err?.message || String(err) });
      }
    });

    this.handleEvent('p2p_request_handoff', async (payload) => {
      if (!invoke) {
        push('p2p_lan_sync_error', { message: 'LAN handoff requires the desktop app.' });
        return;
      }
      const deviceId = payload.device_id || payload['device_id'] || '';
      const bundles = payload.bundles || payload['bundles'] || [];
      try {
        await invoke('p2p_request_handoff', { deviceId, bundles });
        push('p2p_lan_handoff_complete', { device_id: deviceId });
      } catch (err) {
        push('p2p_lan_sync_error', { message: err?.message || String(err) });
      }
    });
  },

  destroyed() {
    if (this.unlisteners) {
      for (const unlisten of this.unlisteners) {
        unlisten();
      }
    }
  },
};

const P2pLanSync = {
  mounted() {
    this.unlisteners = [];
    const invoke = window.__TAURI__?.core?.invoke;
    const eventApi = window.__TAURI__?.event;
    const push = (event, payload) => {
      this.pushEvent(event, payload || {});
    };

    const listenTauri = (name, handler) => {
      if (!eventApi?.listen) return;
      eventApi
        .listen(name, handler)
        .then((unlisten) => {
          this.unlisteners.push(unlisten);
        })
        .catch((err) => {
          console.error(`${name} listener failed:`, err);
        });
    };

    listenTauri('p2p:discovery-update', (ev) => {
      push('p2p_lan_discovery_update', ev.payload);
    });

    listenTauri('p2p:handoff-bundle', (ev) => {
      push('p2p_lan_handoff_bundle', ev.payload);
    });

    listenTauri('p2p:handoff-complete', (ev) => {
      push('p2p_lan_handoff_complete', ev.payload);
    });

    listenTauri('p2p:delta-received', (ev) => {
      push('p2p_lan_delta_received', ev.payload);
    });

    listenTauri('p2p:sync-error', (ev) => {
      push('p2p_lan_sync_error', ev.payload);
    });

    this.handleEvent('p2p_push_deltas', async (payload) => {
      if (!invoke) return;
      const updates = payload.updates || payload['updates'] || [];
      const deviceId = payload.device_id || payload['device_id'] || null;
      try {
        await invoke('p2p_push_deltas', { deviceId, updates });
      } catch (err) {
        console.error('p2p_push_deltas failed:', err);
        push('p2p_lan_sync_error', { message: err?.message || String(err) });
      }
    });

    this.handleEvent('p2p_set_item_frontier', async (payload) => {
      if (!invoke) return;
      try {
        await invoke('p2p_set_item_frontier', {
          peerDeviceId:
            payload.peer_device_id || payload['peer_device_id'] || '',
          itemKey: payload.item_key || payload['item_key'] || '',
          snapshotBase64:
            payload.snapshot_base64 || payload['snapshot_base64'] || '',
          snapshotHash: payload.snapshot_hash || payload['snapshot_hash'] || '',
        });
      } catch (err) {
        console.error('p2p_set_item_frontier failed:', err);
      }
    });
  },

  destroyed() {
    if (this.unlisteners) {
      for (const unlisten of this.unlisteners) {
        unlisten();
      }
    }
  },
};

function installBrokerSidecarBridge(liveSocket) {
  if (window.__suchconfigBrokerBridgeInstalled) return;
  window.__suchconfigBrokerBridgeInstalled = true;

  const pushResult = (event, payload) => {
    const root = document.querySelector('#project-vault-root');
    if (!root) {
      console.error('broker bridge: #project-vault-root not found');
      return;
    }

    const view = liveSocket.owner(root);
    if (!view) {
      console.error('broker bridge: no LiveView owns #project-vault-root');
      return;
    }

    view.pushHookEvent(root, null, event, payload);
  };

  const normalizeStatus = (status, errorMessage) => {
    if (!status) {
      return {
        running: false,
        scope_id: '',
        socket_path: '',
        error: errorMessage || 'Broker request failed.',
      };
    }

    return {
      running: status.running === true,
      scope_id: status.scope_id || '',
      socket_path: status.socket_path || '',
      manifest_loaded: status.manifest_loaded === true,
      health_status: status.health_status || null,
      proxy_enabled: status.proxy_enabled === true,
      proxy_url: status.proxy_url || null,
      proxy_ca_cert_path: status.proxy_ca_cert_path || null,
      proxy_ca_fingerprint: status.proxy_ca_fingerprint || null,
      proxy_ca_pinned: status.proxy_ca_pinned === true,
      error: errorMessage || null,
    };
  };

  window.addEventListener('phx:invoke_broker_start', async (event) => {
    const payload = event.detail || {};
    const invoke = window.__TAURI__?.core?.invoke;

    if (!invoke) {
      pushResult('broker_start_result', {
        running: false,
        error: 'Start Broker requires the desktop app.',
      });
      return;
    }

    const scopeId = payload.scope_id || payload.scopeId || '';
    const manifest = payload.manifest || null;
    const enableProxy = payload.enable_proxy === true || payload.enableProxy === true;

    try {
      const status = await invoke('broker_start', { scopeId, manifest, enableProxy });
      pushResult('broker_start_result', normalizeStatus(status));
    } catch (err) {
      console.error('broker_start failed:', err);
      pushResult('broker_start_result', {
        running: false,
        error: err?.message || String(err),
      });
    }
  });

  window.addEventListener('phx:invoke_broker_stop', async () => {
    const invoke = window.__TAURI__?.core?.invoke;

    if (!invoke) {
      pushResult('broker_stop_result', {
        running: false,
        error: 'Stop Broker requires the desktop app.',
      });
      return;
    }

    try {
      const status = await invoke('broker_stop');
      pushResult('broker_stop_result', normalizeStatus(status));
    } catch (err) {
      console.error('broker_stop failed:', err);
      pushResult('broker_stop_result', {
        running: false,
        error: err?.message || String(err),
      });
    }
  });

  window.addEventListener('phx:fetch_broker_status', async (event) => {
    const invoke = window.__TAURI__?.core?.invoke;
    if (!invoke) return;

    const payload = event.detail || {};
    const scopeId = payload.scope_id || payload.scopeId || null;

    try {
      const status = await invoke('broker_status', { scopeId });
      pushResult('broker_status_result', normalizeStatus(status));
    } catch (err) {
      console.error('broker_status failed:', err);
      pushResult('broker_status_result', {
        running: false,
        error: err?.message || String(err),
      });
    }
  });
}

function installSentinelBridge(liveSocket) {
  if (window.__suchconfigSentinelBridgeInstalled) return;
  window.__suchconfigSentinelBridgeInstalled = true;

  const pushResult = (event, payload) => {
    const root = document.querySelector('#project-vault-root');
    if (!root) {
      console.error('sentinel bridge: #project-vault-root not found');
      return;
    }

    const view = liveSocket.owner(root);
    if (!view) {
      console.error('sentinel bridge: no LiveView owns #project-vault-root');
      return;
    }

    view.pushHookEvent(root, null, event, payload);
  };

  let progressUnlisten = null;

  const ensureProgressListener = async () => {
    const eventApi = window.__TAURI__?.event;
    if (!eventApi?.listen || progressUnlisten) return;

    progressUnlisten = await eventApi.listen('sentinel:progress', (event) => {
      const payload = event.payload || {};
      pushResult('sentinel_scan_progress', {
        phase: payload.phase || null,
        percent: payload.percent ?? 0,
        message: payload.message || null,
      });
    });
  };

  const runScan = async (command, payload) => {
    const invoke = window.__TAURI__?.core?.invoke;
    const path = payload.path || '';
    const folderId = payload.folder_id ?? payload.folderId;

    if (!invoke) {
      pushResult('sentinel_scan_result', {
        folder_id: folderId,
        path,
        error: 'Security Sentinel requires the desktop app.',
      });
      return;
    }

    await ensureProgressListener();

    try {
      const result = await invoke(command, { path, folderId });
      pushResult('sentinel_scan_result', {
        folder_id: result?.folder_id ?? folderId,
        path: result?.path || path,
        report_path: result?.report_path || null,
        report_card: result?.report_card || null,
      });
    } catch (err) {
      console.error(`${command} failed:`, err);
      pushResult('sentinel_scan_result', {
        folder_id: folderId,
        path,
        error: err?.message || String(err),
      });
    }
  };

  window.addEventListener('phx:invoke_sentinel_onboard', async (event) => {
    await runScan('sentinel_onboard_scan', event.detail || {});
  });

  window.addEventListener('phx:invoke_sentinel_rescan', async (event) => {
    await runScan('sentinel_rescan', event.detail || {});
  });
}

const TrustedFolderSync = {
  mounted() {
    this.unlisteners = [];
    const eventApi = window.__TAURI__?.event;
    const invoke = window.__TAURI__?.core?.invoke;

    const push = (event, payload) => {
      this.pushEvent(event, payload);
    };

    const listenTauri = (name, handler) => {
      if (!eventApi?.listen) return;
      eventApi
        .listen(name, handler)
        .then((unlisten) => {
          this.unlisteners.push(unlisten);
        })
        .catch((err) => {
          console.error(`${name} listener failed:`, err);
        });
    };

    listenTauri('trusted-folder:setup-complete', (ev) => {
      push('trusted_folder_setup_complete', ev.payload);
    });

    listenTauri('trusted-folder:request-initial-export', (ev) => {
      push('trusted_folder_request_initial_export', ev.payload);
    });

    listenTauri('trusted-folder:import-snapshot', (ev) => {
      push('trusted_folder_import_snapshot', ev.payload);
    });

    listenTauri('trusted-folder:synced', (ev) => {
      push('trusted_folder_synced', ev.payload);
    });

    this.handleEvent('fetch_trusted_folder', async () => {
      if (!invoke) return;
      try {
        const info = await invoke('get_trusted_folder');
        push('trusted_folder_status', info);
      } catch (err) {
        console.error('get_trusted_folder failed:', err);
      }
    });

    this.handleEvent('invoke_setup_trusted_folder', async (payload) => {
      if (!invoke) {
        push('trusted_folder_setup_failed', {
          message: 'Trusted Folder setup requires the desktop app.',
        });
        return;
      }
      const forcePicker =
        payload?.force_picker === true || payload?.forcePicker === true;
      try {
        const path = await invoke('setup_trusted_folder', { forcePicker });
        push('trusted_folder_setup_done', { path });
      } catch (err) {
        push('trusted_folder_setup_failed', {
          message: err?.message || String(err),
        });
      }
    });

    this.handleEvent('trusted_folder_push_sync', async (payload) => {
      if (!invoke) return;
      const vaults = payload.vaults || payload['vaults'] || [];
      const masterKey = payload.master_key || payload['master_key'] || null;
      try {
        for (const entry of vaults) {
          const vault = entry.vault || entry['vault'];
          const snapshotBase64 =
            entry.snapshot_base64 || entry['snapshot_base64'];
          if (!vault || !snapshotBase64) continue;
          await invoke('trusted_folder_register_snapshot', {
            vault,
            snapshotBase64,
          });
          if (entry.final || entry['final']) {
            await invoke('force_sync_trusted_folder', { masterKey });
          }
        }
      } catch (err) {
        console.error('trusted_folder_push_sync failed:', err);
        push('trusted_folder_sync_failed', {
          message: err?.message || String(err),
        });
      }
    });

    this.handleEvent('verify_trusted_folder_integrity', async (payload) => {
      if (!invoke) {
        push('trusted_folder_sync_failed', {
          message: 'Archive verification requires the desktop app.',
        });
        return;
      }
      const masterKey = payload.master_key || payload['master_key'] || null;
      try {
        const report = await invoke('verify_trusted_folder_integrity', { masterKey });
        push('trusted_folder_verify_result', report);
      } catch (err) {
        push('trusted_folder_sync_failed', {
          message: err?.message || String(err),
        });
      }
    });

    if (invoke) {
      invoke('get_trusted_folder')
        .then((info) => push('trusted_folder_status', info))
        .catch((err) => console.error('get_trusted_folder failed:', err));
    }
  },

  destroyed() {
    if (this.unlisteners) {
      for (const unlisten of this.unlisteners) {
        unlisten();
      }
    }
  },
};

const ArchiveExportFolderPicker = {
  mounted() {
    this.handleClick = async (e) => {
      e.preventDefault();
      e.stopPropagation();

      if (window.__TAURI__) {
        try {
          const { invoke } = window.__TAURI__.core;
          const path = await invoke('select_vault_export_folder');
          if (path) {
            this.pushEvent('archive_export_folder_selected', { path });
          }
        } catch (err) {
          console.error('Failed to select export folder:', err);
        }
      } else {
        console.warn('Tauri API not available — use the desktop app to pick an export folder.');
      }
    };

    this.el.addEventListener('click', this.handleClick);
  },

  destroyed() {
    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }
  },
};

const DownloadHook = {
  mounted() {
    this.handleEvent('save_archive_export', async (payload) => {
      const full_path = payload.full_path ?? payload['full_path'];
      const content_base64 = payload.content_base64 ?? payload['content_base64'];
      const tauriCore = window.__TAURI__?.core;
      if (!tauriCore || typeof tauriCore.invoke !== 'function') {
        return;
      }
      try {
        await tauriCore.invoke('write_archive_export', {
          path: full_path,
          contentBase64: content_base64,
        });
        this.pushEvent('export_success', {
          filename: full_path.split('/').pop() || 'export.suchvault',
          path: full_path,
        });
      } catch (err) {
        console.error('write_archive_export failed:', err);
      }
    });

    this.handleEvent('download', async (payload) => {
      const { filename, mime_type, encoding } = payload;
      const rawContent = payload.content;
      const extension = filename?.split('.').pop() || 'txt';
      let defaultName;
      if (filename && filename.includes('.')) {
        defaultName = filename;
      } else {
        defaultName = (filename || 'export') + '.' + extension;
      }

      let filterName = 'All Files';
      let filterExtensions = ['*'];
      if (extension === 'json') {
        filterName = 'JSON Files';
        filterExtensions = ['json'];
      } else if (extension === 'yaml' || extension === 'yml') {
        filterName = 'YAML Files';
        filterExtensions = ['yaml', 'yml'];
      } else if (extension === 'xml') {
        filterName = 'XML Files';
        filterExtensions = ['xml'];
      } else if (extension === 'csv') {
        filterName = 'CSV Files';
        filterExtensions = ['csv'];
      } else if (extension === 'tsv') {
        filterName = 'TSV Files';
        filterExtensions = ['tsv'];
      } else if (extension === 'suchvault' || extension === 'suchconfig') {
        filterName = 'SuchConfig vault archives';
        filterExtensions = ['suchvault', 'suchconfig'];
      }

      const tauriCore = window.__TAURI__?.core;
      if (tauriCore && typeof tauriCore.invoke === 'function') {
        try {
          const { invoke } = tauriCore;

          const invokeArgs = {
            defaultName: defaultName,
            filterName: filterName,
            filterExtensions: filterExtensions,
          };
          if (encoding === 'base64') {
            invokeArgs.content = null;
            invokeArgs.contentBase64 = rawContent;
          } else {
            invokeArgs.content = rawContent;
            invokeArgs.contentBase64 = null;
          }

          const savedPath = await invoke('save_file_dialog', invokeArgs);

          if (savedPath) {
            this.pushEvent('export_success', {
              filename: savedPath.split('/').pop() || defaultName,
              path: savedPath,
            });
          } else {
            this.pushEvent('export_cancelled', {});
          }
        } catch (err) {
          console.error(
            'Tauri save dialog failed, falling back to browser download:',
            err
          );
          this.browserDownload(rawContent, defaultName, mime_type, encoding);
          this.pushEvent('export_success', { filename: defaultName });
        }
      } else {
        this.browserDownload(rawContent, defaultName, mime_type, encoding);
        this.pushEvent('export_success', { filename: defaultName });
      }
    });
  },

  browserDownload(content, filename, mime_type, encoding) {
    let blobSource = content;
    if (encoding === 'base64' && typeof content === 'string') {
      const binary = atob(content);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      blobSource = bytes;
    }
    const blob = new Blob([blobSource], {
      type: mime_type || 'application/octet-stream',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  },
};

const JobFilesHook = {
  mounted() {
    const myJobsHookId = 'my-jobs-files-hook';
    const csvJobFilesHookId = 'csv-job-files-hook';
    const jwtJobFilesHookId = 'jwt-job-files-hook';
    const jsonJobFilesHookId = 'json-job-files-hook';
    const jobBundleHookIds = new Set([
      csvJobFilesHookId,
      jwtJobFilesHookId,
      jsonJobFilesHookId,
    ]);
    const jobSourceReadHookIds = new Set([
      csvJobFilesHookId,
      jwtJobFilesHookId,
      jsonJobFilesHookId,
    ]);
    const hookElId = this.el && this.el.id;

    this.handleEvent('save_job_bundle', async (payload) => {
      if (!jobBundleHookIds.has(hookElId)) {
        return;
      }
      const root = payload && payload.root;
      const slug = payload && payload.slug;
      const files = (payload && payload.files) || [];
      if (!root || !slug) {
        this.pushEvent('job_save_error', { message: 'Missing root or slug' });
        return;
      }
      if (!window.__TAURI__) {
        this.pushEvent('job_save_error', {
          message: 'Job save requires the desktop app',
        });
        return;
      }
      try {
        const { invoke } = window.__TAURI__.core;
        const normalized = files.map((f) => ({
          relative_path: f.relative_path || f.path,
          content: f.content != null ? String(f.content) : '',
        }));
        const dir = await invoke('save_job_files', {
          root,
          slug,
          files: normalized,
        });
        this.pushEvent('job_save_ok', {
          directory_path: dir,
          job_id: payload.job_id,
          title: payload.title != null ? String(payload.title) : '',
        });
      } catch (err) {
        console.error('save_job_files failed', err);
        this.pushEvent('job_save_error', {
          message: err && err.toString ? err.toString() : 'Save failed',
          job_id: payload.job_id,
        });
      }
    });

    this.handleEvent('pick_jobs_root', async () => {
      if (hookElId !== myJobsHookId) {
        return;
      }
      if (!window.__TAURI__) {
        this.pushEvent('jobs_root_picked', { path: null, error: 'not_tauri' });
        return;
      }
      try {
        const { invoke } = window.__TAURI__.core;
        const path = await invoke('select_jobs_folder');
        this.pushEvent('jobs_root_picked', { path: path || null });
      } catch (err) {
        console.error('select_jobs_folder failed', err);
        this.pushEvent('jobs_root_picked', {
          path: null,
          error: err && err.toString ? err.toString() : 'pick_failed',
        });
      }
    });

    this.handleEvent('reveal_job_in_file_manager', async (payload) => {
      if (hookElId !== myJobsHookId) {
        return;
      }
      const dirPath = payload && payload.path;
      if (!dirPath) {
        return;
      }
      if (!window.__TAURI__) {
        this.pushEvent('reveal_job_fs_done', { ok: false, message: 'not_tauri' });
        return;
      }
      try {
        const { invoke } = window.__TAURI__.core;
        await invoke('reveal_path_in_file_manager', { path: dirPath });
        this.pushEvent('reveal_job_fs_done', { ok: true });
      } catch (err) {
        console.error('reveal_path_in_file_manager failed', err);
        this.pushEvent('reveal_job_fs_done', {
          ok: false,
          message: err && err.toString ? err.toString() : 'reveal_failed',
        });
      }
    });

    this.handleEvent('delete_job_fs', async (payload) => {
      if (hookElId !== myJobsHookId) {
        return;
      }
      const dirPath = payload && payload.directory_path;
      if (!dirPath) {
        this.pushEvent('job_delete_fs_done', { ok: true, job_id: payload.job_id });
        return;
      }
      if (!window.__TAURI__) {
        this.pushEvent('job_delete_fs_done', {
          ok: true,
          job_id: payload.job_id,
          skipped: true,
        });
        return;
      }
      try {
        const { invoke } = window.__TAURI__.core;
        await invoke('remove_path', { path: dirPath });
        this.pushEvent('job_delete_fs_done', { ok: true, job_id: payload.job_id });
      } catch (err) {
        console.error('remove_path failed', err);
        this.pushEvent('job_delete_fs_done', {
          ok: false,
          job_id: payload.job_id,
          message: err && err.toString ? err.toString() : 'delete_failed',
        });
      }
    });

    this.handleEvent('read_job_source_file', async (payload) => {
      if (!jobSourceReadHookIds.has(hookElId)) {
        return;
      }
      const path = payload && payload.path;
      if (!path) {
        this.pushEvent('job_source_load_failed', { reason: 'no_path' });
        return;
      }
      if (!window.__TAURI__) {
        this.pushEvent('job_source_load_failed', { reason: 'not_tauri' });
        return;
      }
      try {
        const { invoke } = window.__TAURI__.core;
        const data = await invoke('read_file_content', { path });
        this.pushEvent('job_source_loaded', {
          filename: data.filename,
          size: data.size,
          content: data.content,
          path: data.path,
          read_seq: payload.read_seq,
        });
      } catch (err) {
        console.error('read_job_source_file failed', err);
        this.pushEvent('job_source_load_failed', {
          reason: err && err.toString ? err.toString() : 'read_failed',
        });
      }
    });
  },
};

const CommandPaletteHotkey = {
  mounted() {
    this.onKey = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        this.pushEvent('open_command_palette');
      }
    };
    window.addEventListener('keydown', this.onKey);
  },
  destroyed() {
    if (this.onKey) {
      window.removeEventListener('keydown', this.onKey);
    }
  },
};

const CommandPalette = {
  mounted() {
    this.input = this.el.querySelector('#command-palette-input');
    this.focusInput();
    this.onKey = (e) => this.handleKey(e);
    window.addEventListener('keydown', this.onKey, true);
  },
  updated() {
    this.input = this.el.querySelector('#command-palette-input');
    this.focusInput();
  },
  destroyed() {
    if (this.onKey) {
      window.removeEventListener('keydown', this.onKey, true);
    }
  },
  focusInput() {
    if (this.input) {
      requestAnimationFrame(() => this.input.focus());
    }
  },
  handleKey(e) {
    if (!this.el.isConnected) {
      return;
    }
    const tag = e.target && e.target.tagName;
    if (
      tag === 'INPUT' &&
      e.target.id !== 'command-palette-input' &&
      e.target.id !== 'topbar-command-input'
    ) {
      return;
    }
    if (e.key === 'Escape') {
      e.preventDefault();
      this.pushEvent('command_palette_key', { key: 'Escape' });
      return;
    }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
      e.preventDefault();
      this.pushEvent('command_palette_key', { key: e.key });
    }
  },
};

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content');

(async () => {
  try {
    // @ts-ignore - phoenix-colocated is generated at build time
    const colocatedModule = await import(
      'phoenix-colocated/suchconfig_desktop'
    );
    colocatedHooks = colocatedModule.hooks || {};
  } catch (e) {
    console.warn(
      'Colocated hooks not available (this is normal if no colocated hooks exist)'
    );
  }

  const ThemeToggle = {
    mounted() {
      this.updateToggleVisibility();
      this.observer = new MutationObserver(() => this.updateToggleVisibility());
      this.observer.observe(document.documentElement, {
        attributes: true,
        attributeFilter: ['data-theme'],
      });
    },

    updateToggleVisibility() {
      const theme = document.documentElement.getAttribute('data-theme');
      const lightBtn = document.getElementById('theme-toggle-light');
      const darkBtn = document.getElementById('theme-toggle-dark');

      if (lightBtn && darkBtn) {
        if (theme === 'dark') {
          lightBtn.classList.add('hidden');
          darkBtn.classList.remove('hidden');
        } else {
          lightBtn.classList.remove('hidden');
          darkBtn.classList.add('hidden');
        }
      }
    },

    destroyed() {
      if (this.observer) {
        this.observer.disconnect();
      }
    },
  };

  const liveSocket = new LiveSocket('/live', Socket, {
    longPollFallbackMs: 2500,
    params: { _csrf_token: csrfToken },
    hooks: {
      CommandPalette,
      CommandPaletteHotkey,
      TagPicker,
      NewEntryTypePicker,
      CopyButton,
      CopyPathHook,
      ToastAutoDismiss,
      ResizableSplit,
      TextareaValueHook,
      VaultKeyStore,
      LinkedProjectSync,
      GlobalPasskeyNative,
      DropZone,
      ThemeToggle,
      MarkdownWorkspace,
      ArchiveExportFolderPicker,
      TrustedFolderSync,
      P2pPairingSync,
      P2pLanSync,
      Download: DownloadHook,
      ...colocatedHooks,
    },
  });

  liveSocket.connect();
  installBrokerSidecarBridge(liveSocket);
  installSentinelBridge(liveSocket);

  topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });
  window.addEventListener('phx:page-loading-start', (_info) =>
    topbar.show(300)
  );
  window.addEventListener('phx:page-loading-stop', (_info) => topbar.hide());

  window.liveSocket = liveSocket;
})();

// Global function to navigate to a page by clicking the hidden button
window.navigateToPage = function (page) {
  console.log('navigateToPage called with page:', page);
  const hiddenButton = document.getElementById('hidden-navigate-button');
  if (hiddenButton) {
    console.log(
      'navigateToPage: Found hidden button, updating phx-value-page to:',
      page
    );
    hiddenButton.setAttribute('phx-value-page', page);
    // Use a small delay to ensure the attribute is set
    setTimeout(() => {
      console.log('navigateToPage: Clicking hidden button');
      const clickEvent = new MouseEvent('click', {
        bubbles: true,
        cancelable: true,
        view: window,
      });
      hiddenButton.dispatchEvent(clickEvent);
    }, 50);
  } else {
    console.error('navigateToPage: Hidden button not found!');
  }
};

const normalizeNativePasskeyResponse = (payload, defaults = {}) => {
  const source = payload && typeof payload === 'object' ? payload : {};
  return {
    ok: false,
    supported: false,
    stub: true,
    platform: 'unknown',
    provider: 'unknown',
    code: 'unknown',
    message: '',
    reason: null,
    reason_code: null,
    ...defaults,
    ...source,
  };
};

const nativePasskeyInvokeError = (error, defaults = {}) =>
  normalizeNativePasskeyResponse(
    {
      ok: false,
      code: 'invoke_failed',
      message: error?.message || 'Native passkey invocation failed.',
    },
    defaults
  );

function biometryStatusToPasskeyAvailability(status) {
  const platform = typeof navigator !== 'undefined' && navigator.platform ? navigator.platform.toLowerCase() : 'unknown';
  const supported = status && status.isAvailable === true;
  const provider = supported ? 'tauri_plugin_biometry' : 'tauri_plugin_biometry';
  return normalizeNativePasskeyResponse(
    {
      ok: supported,
      supported: status != null,
      code: supported ? 'ready_for_native_integration' : (status && status.errorCode) || 'unavailable',
      message: supported ? 'Biometry available (Touch ID or device credential).' : (status && status.error) || 'Biometry not available.',
      platform: platform.includes('mac') ? 'macos' : platform.includes('win') ? 'windows' : platform,
      stub: false,
      provider,
    },
    { platform: 'desktop', provider: 'tauri_bridge' }
  );
}

window.SuchConfigNativePasskey = {
  available() {
    if (!window.__TAURI__) {
      return Promise.resolve(
        normalizeNativePasskeyResponse(
          {
            code: 'no_tauri_runtime',
            message: 'Native passkey requires SuchConfig Desktop runtime.',
          },
          {
            platform: 'browser',
            provider: 'no_tauri_runtime',
          }
        )
      );
    }

    const { invoke } = window.__TAURI__.core;
    return invoke('plugin:biometry|status')
      .then((status) => biometryStatusToPasskeyAvailability(status))
      .catch(() =>
        invoke('native_global_passkey_availability')
          .then((payload) =>
            normalizeNativePasskeyResponse(payload, {
              code: 'unknown',
              message: 'Native passkey availability status returned.',
            })
          )
          .catch((error) =>
            nativePasskeyInvokeError(error, {
              provider: 'tauri_bridge',
              platform: 'desktop',
            })
          )
      );
  },

  authenticate(reason) {
    if (!window.__TAURI__) {
      return Promise.resolve(
        normalizeNativePasskeyResponse(
          {
            authenticated: false,
            code: 'no_tauri_runtime',
            message: 'Native passkey auth requires SuchConfig Desktop runtime.',
          },
          {
            platform: 'browser',
            provider: 'no_tauri_runtime',
          }
        )
      );
    }

    const { invoke } = window.__TAURI__.core;
    return invoke('plugin:biometry|authenticate', {
      reason: reason || 'Authenticate for Global Passkey',
      options: {
        allowDeviceCredential: true,
        fallbackTitle: 'Use Passcode',
        cancelTitle: 'Cancel',
        confirmationRequired: false,
      },
    })
      .then(() =>
        normalizeNativePasskeyResponse(
          { ok: true, authenticated: true },
          { authenticated: false }
        )
      )
      .catch((error) =>
        normalizeNativePasskeyResponse(
          {
            ok: false,
            authenticated: false,
            code: error?.code || 'auth_failed',
            message: error?.message || 'Authentication failed or was canceled.',
          },
          { authenticated: false, provider: 'tauri_plugin_biometry', platform: 'desktop' }
        )
      );
  },

  storeWrappedKey(keyId, wrappedKey) {
    if (!window.__TAURI__) {
      return Promise.resolve(
        normalizeNativePasskeyResponse(
          {
            stored: false,
            code: 'no_tauri_runtime',
            message: 'Wrapped key storage requires SuchConfig Desktop runtime.',
          },
          {
            platform: 'browser',
            provider: 'no_tauri_runtime',
          }
        )
      );
    }

    const { invoke } = window.__TAURI__.core;
    return invoke('native_global_passkey_store_wrapped_key', {
      key_id: keyId,
      wrapped_key: wrappedKey,
    })
      .then((payload) =>
        normalizeNativePasskeyResponse(payload, {
          stored: false,
        })
      )
      .catch((error) =>
        nativePasskeyInvokeError(error, {
          stored: false,
          provider: 'tauri_bridge',
          platform: 'desktop',
        })
      );
  },

  loadWrappedKey(keyId) {
    if (!window.__TAURI__) {
      return Promise.resolve(
        normalizeNativePasskeyResponse(
          {
            found: false,
            wrapped_key: null,
            code: 'no_tauri_runtime',
            message: 'Wrapped key loading requires SuchConfig Desktop runtime.',
          },
          {
            platform: 'browser',
            provider: 'no_tauri_runtime',
          }
        )
      );
    }

    const { invoke } = window.__TAURI__.core;
    return invoke('native_global_passkey_load_wrapped_key', {
      key_id: keyId,
    })
      .then((payload) =>
        normalizeNativePasskeyResponse(payload, {
          found: false,
          wrapped_key: null,
        })
      )
      .catch((error) =>
        nativePasskeyInvokeError(error, {
          found: false,
          wrapped_key: null,
          provider: 'tauri_bridge',
          platform: 'desktop',
        })
      );
  },

  clearWrappedKey(keyId) {
    if (!window.__TAURI__) {
      return Promise.resolve(
        normalizeNativePasskeyResponse(
          {
            cleared: false,
            code: 'no_tauri_runtime',
            message: 'Wrapped key clearing requires SuchConfig Desktop runtime.',
          },
          {
            platform: 'browser',
            provider: 'no_tauri_runtime',
          }
        )
      );
    }

    const { invoke } = window.__TAURI__.core;
    return invoke('native_global_passkey_clear_wrapped_key', {
      key_id: keyId,
    })
      .then((payload) =>
        normalizeNativePasskeyResponse(payload, {
          cleared: false,
        })
      )
      .catch((error) =>
        nativePasskeyInvokeError(error, {
          cleared: false,
          provider: 'tauri_bridge',
          platform: 'desktop',
        })
      );
  },
};

// Listen for navigate-parent events from child LiveViews and trigger parent navigation
// This listens at the document level to catch events from any LiveView
document.addEventListener('phx:navigate-parent', (e) => {
  const page = e.detail.page;
  console.log(
    'Document listener: Received navigate-parent event for page:',
    page
  );

  // Find all LiveView containers to get the parent
  const allViews = document.querySelectorAll('[data-phx-view]');
  let parentView = null;

  // Find the root view (parent) - the one that doesn't have a parent with data-phx-view
  for (let view of allViews) {
    if (!view.closest('[data-phx-view]')) {
      parentView = view;
      break;
    }
  }

  // Always use the hidden button approach - it's more reliable
  const hiddenButton = document.getElementById('hidden-navigate-button');
  if (hiddenButton) {
    console.log(
      'Document listener: Found hidden button, updating phx-value-page to:',
      page
    );
    hiddenButton.setAttribute('phx-value-page', page);
    // Force LiveView to recognize the attribute change
    hiddenButton.dispatchEvent(new Event('input', { bubbles: true }));
    setTimeout(() => {
      console.log('Document listener: Clicking hidden button');
      // Create a proper click event
      const clickEvent = new MouseEvent('click', {
        bubbles: true,
        cancelable: true,
        view: window,
      });
      hiddenButton.dispatchEvent(clickEvent);
    }, 100);
  } else {
    console.error('Document listener: Hidden button not found!');
  }
});

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// (liveSocket is now exposed in the async IIFE above)

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === 'development') {
  window.addEventListener(
    'phx:live_reload:attached',
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener('keydown', (e) => (keyDown = e.key));
      window.addEventListener('keyup', (e) => (keyDown = null));
      window.addEventListener(
        'click',
        (e) => {
          if (keyDown === 'c') {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === 'd') {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true
      );

      window.liveReloader = reloader;
    }
  );
}
