import Foundation
import CoreLocation

/// Smart Shift Detection (#3): energy-frugal geofencing around work locations.
/// Monitors circular regions for the saved workplaces and reports when the user
/// leaves one, so the app can propose a shift extension / overtime.
///
/// This only does something on a real device with location permission. In the
/// simulator/CI it compiles and stays idle; the detection flow can also be
/// triggered manually ("Erkennung simulieren") for testing.
final class LocationMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationMonitor()

    private let manager = CLLocationManager()
    @Published var authorized = false

    /// Called when the user leaves a monitored workplace region.
    var onLeaveWorkplace: ((Date) -> Void)?
    /// One-shot capture completion (for "save current location as workplace").
    private var captureHandler: ((CLLocationCoordinate2D?) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        refreshAuthorized()
    }

    // MARK: Authorization

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    private func refreshAuthorized() {
        let s = manager.authorizationStatus
        authorized = (s == .authorizedAlways || s == .authorizedWhenInUse)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorized()
    }

    // MARK: Capture current location (to save a workplace)

    func captureCurrent(_ completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard authorized else { completion(nil); return }
        captureHandler = completion
        manager.requestLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        captureHandler?(locations.last?.coordinate)
        captureHandler = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        captureHandler?(nil)
        captureHandler = nil
    }

    // MARK: Region monitoring

    /// Starts monitoring the given workplaces (replaces any existing regions).
    func startMonitoring(_ workplaces: [Workplace]) {
        guard authorized, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
        for w in workplaces {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude),
                radius: max(50, min(w.radiusMeters, 400)),
                identifier: w.id.uuidString)
            region.notifyOnEntry = false
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
    }

    func stopAll() {
        for region in manager.monitoredRegions { manager.stopMonitoring(for: region) }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        onLeaveWorkplace?(Date())
    }
}
