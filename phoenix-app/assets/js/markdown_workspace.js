import { marked } from 'marked';
import DOMPurify from 'dompurify';
import hljs from 'highlight.js';

marked.use({
  gfm: true,
  breaks: false,
});

const languageAliases = {
  ts: 'typescript',
  js: 'javascript',
  mjs: 'javascript',
  cjs: 'javascript',
  sh: 'bash',
  yml: 'yaml',
  md: 'markdown',
  ex: 'elixir',
  exs: 'elixir',
  rs: 'rust',
  rb: 'ruby',
  py: 'python',
  hcl: 'terraform',
  tf: 'terraform',
  vue: 'xml',
};

const highlightAutoLanguages = [
  'typescript',
  'javascript',
  'bash',
  'json',
  'css',
  'xml',
  'markdown',
  'python',
  'elixir',
  'rust',
  'go',
  'sql',
  'yaml',
  'dockerfile',
];

const debounce = (fn, ms) => {
  let t = null;
  return (...args) => {
    if (t) clearTimeout(t);
    t = setTimeout(() => {
      t = null;
      fn(...args);
    }, ms);
  };
};

function scrollRatio(el) {
  const max = el.scrollHeight - el.clientHeight;
  if (max <= 0) return 0;
  return el.scrollTop / max;
}

function setScrollRatio(el, ratio) {
  const max = el.scrollHeight - el.clientHeight;
  const next = max > 0 ? ratio * max : 0;
  el.scrollTop = next;
  return next;
}

function languageFromCodeElement(el) {
  const m = (el.getAttribute('class') || '').match(
    /(?:^|\s)language-([a-zA-Z0-9#+-]+)/
  );
  return m && m[1] ? m[1].toLowerCase() : null;
}

function applyAutoHighlight(block, source) {
  const auto = hljs.highlightAuto(source, highlightAutoLanguages);
  const lang = auto.language || 'plaintext';
  block.className = `language-${lang} hljs`;
  block.innerHTML = auto.value;
}

function applySyntaxHighlighting(root) {
  if (!root) return;
  const blocks = root.querySelectorAll('pre code');
  blocks.forEach((block) => {
    if (!(block instanceof HTMLElement)) {
      return;
    }
    let name = languageFromCodeElement(block);
    if (name) {
      const full = languageAliases[name];
      if (full && !hljs.getLanguage(name) && hljs.getLanguage(full)) {
        const cls = block.className.replace(
          new RegExp(`\\blanguage-${name}\\b`, 'g'),
          `language-${full}`
        );
        block.setAttribute('class', cls);
        name = full;
      }
    }
    const source = block.textContent || '';
    if (!name) {
      applyAutoHighlight(block, source);
      return;
    }
    if (!hljs.getLanguage(name)) {
      applyAutoHighlight(block, source);
      return;
    }
    try {
      hljs.highlightElement(block);
    } catch (_e) {
      applyAutoHighlight(block, source);
    }
  });
}

export const MarkdownWorkspace = {
  mounted() {
    const initial = (this.el.dataset.defaultMode || 'split').trim() || 'split';
    this.mode = initial;
    this.syncedScrollTops = new WeakMap();

    this.onInput = debounce(() => this.renderPreview(), 120);
    this.onEditorScroll = (e) => this.handleScroll(e, this.preview);
    this.onPreviewScroll = (e) => this.handleScroll(e, this.textarea);
    this.onModeClick = (e) => {
      const btn = e.target.closest('[data-md-mode]');
      if (!btn || !this.el.contains(btn)) return;
      e.preventDefault();
      const next = btn.getAttribute('data-md-mode');
      if (!next) return;
      this.setMode(next);
    };

    this.attachTextarea();
    this.attachPreview();
    this.el.addEventListener('click', this.onModeClick);
    this.setMode(this.mode);
    this.renderPreview();
  },

  updated() {
    this.attachPreview();
    this.attachTextarea();
    this.renderPreview();
  },

  attachTextarea() {
    const next = this.el.querySelector('textarea[name="note_raw_content"]');
    if (next === this.textarea) {
      return;
    }
    if (this.textarea && this.onInput) {
      this.textarea.removeEventListener('input', this.onInput);
      this.textarea.removeEventListener('scroll', this.onEditorScroll);
    }
    this.textarea = next;
    if (this.textarea) {
      this.textarea.addEventListener('input', this.onInput);
      this.textarea.addEventListener('scroll', this.onEditorScroll);
    }
  },

  attachPreview() {
    const next = this.el.querySelector('[data-md-preview]');
    if (next === this.preview) {
      return;
    }
    if (this.preview && this.onPreviewScroll) {
      this.preview.removeEventListener('scroll', this.onPreviewScroll);
    }
    this.preview = next;
    if (this.preview) {
      this.preview.addEventListener('scroll', this.onPreviewScroll);
    }
  },

  destroyed() {
    if (this.textarea && this.onInput) {
      this.textarea.removeEventListener('input', this.onInput);
      this.textarea.removeEventListener('scroll', this.onEditorScroll);
    }
    if (this.preview && this.onPreviewScroll) {
      this.preview.removeEventListener('scroll', this.onPreviewScroll);
    }
    if (this.onModeClick) {
      this.el.removeEventListener('click', this.onModeClick);
    }
  },

  handleScroll(e, target) {
    const source = e.currentTarget;
    if (!source || !target) return;
    const expected = this.syncedScrollTops.get(source);
    if (expected !== undefined && Math.abs(source.scrollTop - expected) < 1) {
      this.syncedScrollTops.delete(source);
      return;
    }
    const next = setScrollRatio(target, scrollRatio(source));
    this.syncedScrollTops.set(target, next);
  },

  setMode(mode) {
    this.mode = mode;
    this.el.dataset.mode = mode;
    this.el.querySelectorAll('[data-md-mode]').forEach((btn) => {
      const active = btn.getAttribute('data-md-mode') === mode;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    this.renderPreview();
  },

  renderPreview() {
    if (!this.preview || !this.textarea) return;
    const raw = this.textarea.value || '';
    let html = '';
    try {
      html = marked.parse(raw, { async: false });
    } catch (_e) {
      html = '<p class="text-red-600 dark:text-red-400">Unable to render preview.</p>';
    }
    const clean = DOMPurify.sanitize(html, {
      USE_PROFILES: { html: true },
    });
    this.preview.innerHTML = clean;
    applySyntaxHighlighting(this.preview);
    if (this.textarea) {
      setScrollRatio(this.preview, scrollRatio(this.textarea));
    }
  },
};
