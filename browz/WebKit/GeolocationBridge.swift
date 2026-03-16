import CoreLocation
import Foundation
import WebKit

/// Injects a script that overrides navigator.geolocation and bridges to the app's
/// CLLocationManager so sites get location using the app's single TCC permission.
@MainActor
final class GeolocationBridge: NSObject {
    static let messageHandlerName = "browzGeolocation"

    private let locationManager = CLLocationManager()
    /// Resolves permission for a host (uses stored allow/deny or shows prompt and saves).
    private var resolvePermission: (String, @escaping (Bool) -> Void) -> Void
    private var pendingRequest: (requestId: String, webView: WKWebView, isWatch: Bool)?

    override init() {
        self.resolvePermission = { _, done in done(false) }
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func setResolvePermission(_ block: @escaping (String, @escaping (Bool) -> Void) -> Void) {
        resolvePermission = block
    }

    private static let injectScript: WKUserScript = {
        let js = """
        (function() {
          if (!window.navigator || !window.navigator.geolocation) return;
          var __browzGeoCallbacks = {};
          function __browzNextId() { return 'browz_geo_' + Date.now() + '_' + Math.random().toString(36).slice(2); }
          navigator.geolocation.getCurrentPosition = function(success, error, options) {
            var id = __browzNextId();
            __browzGeoCallbacks[id] = { success: success || function(){}, error: error || function(e){}, watch: false };
            webkit.messageHandlers.browzGeolocation.postMessage({ type: 'getCurrentPosition', requestId: id });
          };
          navigator.geolocation.watchPosition = function(success, error, options) {
            var id = __browzNextId();
            __browzGeoCallbacks[id] = { success: success || function(){}, error: error || function(e){}, watch: true };
            webkit.messageHandlers.browzGeolocation.postMessage({ type: 'watchPosition', requestId: id });
            return id;
          };
          navigator.geolocation.clearWatch = function(watchId) {
            delete __browzGeoCallbacks[watchId];
            webkit.messageHandlers.browzGeolocation.postMessage({ type: 'clearWatch', watchId: watchId });
          };
          window.__browzGeoResolve = function(requestId, data, isError) {
            var c = __browzGeoCallbacks[requestId];
            if (!c) return;
            try {
              if (isError) c.error(data); else c.success(data);
            } catch (e) {}
            if (!c.watch) delete __browzGeoCallbacks[requestId];
          };
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }()

    static var userScript: WKUserScript { injectScript }
}

extension GeolocationBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            await handleMessage(message)
        }
    }

    private func handleMessage(_ message: WKScriptMessage) async {
        guard let webView = message.webView,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let requestId = body["requestId"] as? String else { return }

        let host = webView.url?.host ?? ""

        switch type {
        case "getCurrentPosition":
            await performRequest(webView: webView, requestId: requestId, host: host, isWatch: false)
        case "watchPosition":
            await performRequest(webView: webView, requestId: requestId, host: host, isWatch: true)
        case "clearWatch":
            if pendingRequest?.requestId == body["watchId"] as? String {
                locationManager.stopUpdatingLocation()
                pendingRequest = nil
            }
            return
        default:
            return
        }
    }

    private func performRequest(webView: WKWebView, requestId: String, host: String, isWatch: Bool) async {
        let hostForPrompt = host.isEmpty ? "this page" : host
        let allowed: Bool = await withCheckedContinuation { cont in
            resolvePermission(hostForPrompt) { cont.resume(returning: $0) }
        }

        guard allowed else {
            resolve(webView: webView, requestId: requestId, errorCode: 1, message: "User denied the request for Geolocation.")
            return
        }

        switch locationManager.authorizationStatus {
        case .denied, .restricted:
            resolve(webView: webView, requestId: requestId, errorCode: 1, message: "Location permission denied.")
            return
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            resolve(webView: webView, requestId: requestId, errorCode: 1, message: "Location permission not yet granted. Allow in the system dialog and try again.")
            return
        case .authorized, .authorizedAlways:
            break
        @unknown default:
            resolve(webView: webView, requestId: requestId, errorCode: 2, message: "Position unavailable.")
            return
        }

        pendingRequest = (requestId, webView, isWatch)
        if isWatch {
            locationManager.startUpdatingLocation()
        } else {
            locationManager.requestLocation()
        }

        // If CoreLocation never calls the delegate (e.g. Location Services off, timeout), resolve after 15s.
        let capturedRequestId = requestId
        let capturedWebView = webView
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if pendingRequest?.requestId == capturedRequestId {
                locationManager.stopUpdatingLocation()
                pendingRequest = nil
                resolve(webView: capturedWebView, requestId: capturedRequestId, errorCode: 3, message: "Location request timed out. Check that Location Services is on for this app.")
            }
        }
    }

    private func resolve(webView: WKWebView, requestId: String, errorCode: Int, message: String) {
        let escapedMsg = message.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = "typeof __browzGeoResolve === 'function' && __browzGeoResolve('\(requestId)', { code: \(errorCode), message: '\(escapedMsg)' }, true);"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func resolve(webView: WKWebView, requestId: String, location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        let acc = location.horizontalAccuracy
        let alt = location.altitude
        let altAcc = location.verticalAccuracy
        let ts = Int64(location.timestamp.timeIntervalSince1970 * 1000)
        let js = """
        (function() {
          if (typeof __browzGeoResolve !== 'function') return;
          __browzGeoResolve('\(requestId)', {
            coords: { latitude: \(lat), longitude: \(lon), accuracy: \(acc), altitude: \(alt), altitudeAccuracy: \(altAcc), heading: null, speed: null },
            timestamp: \(ts)
          }, false);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

extension GeolocationBridge: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            if let pending = pendingRequest {
                resolve(webView: pending.webView, requestId: pending.requestId, location: loc)
                if !pending.isWatch {
                    locationManager.stopUpdatingLocation()
                    pendingRequest = nil
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let pending = pendingRequest {
                let msg = (error as NSError).localizedDescription
                resolve(webView: pending.webView, requestId: pending.requestId, errorCode: 2, message: msg)
                locationManager.stopUpdatingLocation()
                pendingRequest = nil
            }
        }
    }
}
