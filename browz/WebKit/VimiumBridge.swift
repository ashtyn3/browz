import Foundation
import WebKit

/// Injects Vimium-style keyboard navigation: scrolling (j/k, d/u, gg/G), link hints (f/F),
/// and optional back/forward (H/L). Only active when focus is not in an input/textarea/contenteditable.
/// "F" (open link in new tab) is handled via the browzOpenURL message handler.
final class VimiumBridge: NSObject {
    static let messageHandlerName = "browzOpenURL"

    private let onOpenURL: (URL) -> Void

    init(onOpenURL: @escaping (URL) -> Void) {
        self.onOpenURL = onOpenURL
        super.init()
    }

    private static let scrollLineAmount: Int = 80

    private static let injectScript: WKUserScript = {
        let scrollLine = scrollLineAmount
        let js = """
        (function() {
          document.documentElement.style.scrollBehavior = 'smooth';
          if (document.body) document.body.style.scrollBehavior = 'smooth';

          function isEditable() {
            var el = document.activeElement;
            if (!el) return false;
            if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') return true;
            return el.isContentEditable === true;
          }

          var lastGTime = 0;
          var hintState = { active: false, openInNewTab: false, items: [], overlay: null, buffer: '' };

          var scrollIntervalId = null;
          var scrollKey = null;
          var scrollIntervalMs = 70;
          function scrollDown() { window.scrollBy(0, \(scrollLine)); }
          function scrollUp() { window.scrollBy(0, -\(scrollLine)); }
          function halfPageDown() { window.scrollBy(0, window.innerHeight / 2); }
          function halfPageUp() { window.scrollBy(0, -window.innerHeight / 2); }
          function scrollTop() { window.scrollTo(0, 0); }
          function scrollBottom() {
            var d = document.documentElement;
            window.scrollTo(0, Math.max(d.scrollHeight, d.clientHeight));
          }
          function runScrollTick() {
            if (scrollKey === 'j') scrollDown();
            else if (scrollKey === 'k') scrollUp();
            else if (scrollKey === 'd') halfPageDown();
            else if (scrollKey === 'u') halfPageUp();
          }
          function startScrollRepeat(key) {
            if (scrollIntervalId) clearInterval(scrollIntervalId);
            scrollKey = key;
            runScrollTick();
            scrollIntervalId = setInterval(runScrollTick, scrollIntervalMs);
          }
          function stopScrollRepeat() {
            if (scrollIntervalId) { clearInterval(scrollIntervalId); scrollIntervalId = null; }
            scrollKey = null;
          }

          function getClickables() {
            var sel = 'a[href], button, input[type=submit], input[type=button], [role=button]';
            var raw = document.querySelectorAll(sel);
            var list = [];
            for (var i = 0; i < raw.length; i++) {
              var el = raw[i];
              var r = el.getBoundingClientRect();
              if (r.width < 2 || r.height < 2) continue;
              var style = window.getComputedStyle(el);
              if (style.visibility === 'hidden' || style.display === 'none') continue;
              var url = el.href || (el.closest && el.closest('a') && el.closest('a').href) || window.location.href;
              list.push({ el: el, url: url });
            }
            return list;
          }

          function hintString(i) {
            var chars = 'abcdefghijklmnopqrstuvwxyz';
            return chars[Math.floor(i / 26)] + chars[i % 26];
          }

          function exitHintMode() {
            hintState.active = false;
            if (hintState.overlay && hintState.overlay.parentNode) {
              hintState.overlay.parentNode.removeChild(hintState.overlay);
            }
            hintState.overlay = null;
            hintState.items = [];
            hintState.buffer = '';
          }

          function runHint(openInNewTab, item) {
            if (openInNewTab && item.url && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.browzOpenURL) {
              window.webkit.messageHandlers.browzOpenURL.postMessage({ url: item.url });
            } else {
              item.el.click();
            }
          }

          function updateHintOverlay() {
            if (!hintState.overlay) return;
            var buffer = hintState.buffer.toLowerCase();
            var spans = hintState.overlay.querySelectorAll('[data-hint]');
            for (var i = 0; i < spans.length; i++) {
              var span = spans[i];
              var hint = span.getAttribute('data-hint');
              var isPrefix = hint.indexOf(buffer) === 0;
              var isExact = hint === buffer;
              span.style.visibility = isPrefix ? 'visible' : 'hidden';
              span.style.background = isExact ? '#333' : '#ffeb3b';
              span.style.color = isExact ? '#fff' : '#000';
              span.style.fontWeight = isExact ? 'bold' : 'normal';
              span.style.border = isExact ? '2px solid #000' : '1px solid #333';
            }
          }

          function showHints(openInNewTab) {
            var items = getClickables();
            if (items.length === 0) return;
            hintState.active = true;
            hintState.openInNewTab = openInNewTab;
            hintState.items = items.map(function(item, i) { return { el: item.el, url: item.url, hint: hintString(i) }; });
            hintState.buffer = '';

            var overlay = document.createElement('div');
            overlay.setAttribute('id', 'browz-hint-overlay');
            overlay.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647;';
            hintState.items.forEach(function(it) {
              var r = it.el.getBoundingClientRect();
              var span = document.createElement('span');
              span.textContent = it.hint;
              span.style.cssText = 'position:fixed;left:' + r.left + 'px;top:' + r.top + 'px;' +
                'background:#ffeb3b;color:#000;font:11px monospace;padding:1px 3px;border:1px solid #333;border-radius:2px;';
              span.setAttribute('data-hint', it.hint);
              overlay.appendChild(span);
            });
            document.body.appendChild(overlay);
            hintState.overlay = overlay;
            updateHintOverlay();
          }

          document.addEventListener('keydown', function(ev) {
            if (hintState.active) {
              if (ev.key === 'Escape') {
                ev.preventDefault();
                ev.stopPropagation();
                exitHintMode();
                return;
              }
              if (ev.key.length === 1 && !ev.ctrlKey && !ev.metaKey && !ev.altKey) {
                ev.preventDefault();
                ev.stopPropagation();
                hintState.buffer += ev.key.toLowerCase();
                updateHintOverlay();
                var match = hintState.items.filter(function(it) { return it.hint === hintState.buffer; })[0];
                if (match) {
                  exitHintMode();
                  runHint(hintState.openInNewTab, match);
                } else {
                  var maxLen = Math.max.apply(null, hintState.items.map(function(it) { return it.hint.length; }));
                  if (hintState.buffer.length >= maxLen) exitHintMode();
                }
                return;
              }
              return;
            }

            if (isEditable()) return;

            var k = ev.key;
            var handled = true;
            if (k === 'j' || k === 'k' || k === 'd' || k === 'u') {
              if (!ev.repeat) startScrollRepeat(k);
            }
            else if (k === 'g') {
              if (Date.now() - lastGTime < 300) { scrollTop(); lastGTime = 0; } else { lastGTime = Date.now(); }
            }
            else if (k === 'G') { scrollBottom(); }
            else if (k === 'h' || k === 'H') { history.back(); }
            else if (k === 'l' || k === 'L') { history.forward(); }
            else if (k === 'f') { showHints(false); }
            else if (k === 'F') { showHints(true); }
            else { handled = false; }

            if (handled) {
              ev.preventDefault();
              ev.stopPropagation();
            }
          }, true);

          document.addEventListener('keyup', function(ev) {
            if (hintState.active) return;
            var k = ev.key;
            if ((k === 'j' || k === 'k' || k === 'd' || k === 'u') && scrollKey === k) {
              stopScrollRepeat();
              ev.preventDefault();
              ev.stopPropagation();
            }
          }, true);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }()

    static var userScript: WKUserScript { injectScript }
}

extension VimiumBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let urlString = body["url"] as? String,
              let url = URL(string: urlString) else { return }
        onOpenURL(url)
    }
}
