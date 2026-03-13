import Foundation
import WebKit

/// Toggles a clean reader-mode overlay in a WKWebView using JavaScript.
enum ReaderMode {

    // MARK: - Public API

    static func activate(in webView: WKWebView) {
        webView.evaluateJavaScript(activateJS)
    }

    static func deactivate(in webView: WKWebView) {
        webView.evaluateJavaScript(deactivateJS)
    }

    static func checkAvailable(in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        webView.evaluateJavaScript(checkJS) { result, _ in
            completion((result as? Bool) == true)
        }
    }

    // MARK: - JS Source

    private static let activateJS = """
    (function() {
        if (document.getElementById('__aob_reader__')) return;

        // Try common article containers
        var article = document.querySelector('article') ||
                      document.querySelector('[role="main"]') ||
                      document.querySelector('main') ||
                      document.querySelector('.post-content') ||
                      document.querySelector('.article-body') ||
                      document.querySelector('.entry-content') ||
                      document.querySelector('#content') ||
                      document.body;

        var title = document.title;
        var byline = document.querySelector('meta[name="author"]')?.content || '';
        var content = article.innerHTML;

        var overlay = document.createElement('div');
        overlay.id = '__aob_reader__';
        overlay.style.cssText = `
            position: fixed;
            top: 0; left: 0; right: 0; bottom: 0;
            z-index: 2147483647;
            overflow-y: auto;
            background: #FAFAF8;
            padding: 0;
            box-sizing: border-box;
        `;

        overlay.innerHTML = `
            <div style="
                max-width: 660px;
                margin: 0 auto;
                padding: 60px 32px 80px;
                font-family: -apple-system, 'Georgia', serif;
                font-size: 18px;
                line-height: 1.75;
                color: #1a1a1a;
            ">
                <h1 style="
                    font-size: 28px;
                    font-weight: 700;
                    line-height: 1.3;
                    margin: 0 0 8px;
                    color: #111;
                ">${title}</h1>
                ${byline ? '<p style="font-size:13px;color:#888;margin:0 0 32px;">' + byline + '</p>' : '<div style="margin-bottom:32px;border-bottom:1px solid #e0e0e0;"></div>'}
                ${content}
            </div>
        `;

        // Remove ads / nav from cloned content
        overlay.querySelectorAll('script,style,nav,header,footer,aside,[class*="ad"],[id*="ad"],[class*="banner"]')
               .forEach(function(el) { el.remove(); });

        document.body.appendChild(overlay);
        window.__aob_reader_active__ = true;
    })();
    """

    private static let deactivateJS = """
    (function() {
        var overlay = document.getElementById('__aob_reader__');
        if (overlay) { overlay.remove(); }
        window.__aob_reader_active__ = false;
    })();
    """

    private static let checkJS = """
    (function() {
        var article = document.querySelector('article') ||
                      document.querySelector('[role="main"]') ||
                      document.querySelector('main');
        return !!article && document.body.innerText.length > 500;
    })();
    """
}
