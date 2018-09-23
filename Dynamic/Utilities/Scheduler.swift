//
//  Scheduler.swift
//  Dynamic
//
//  Created by Apollo Zhu on 6/13/18.
//  Copyright © 2018 Dynamic Dark Mode. All rights reserved.
//

import CoreLocation
import Solar
import Schedule

public final class Scheduler: NSObject, CLLocationManagerDelegate {
    public static let shared = Scheduler()
    private override init() { super.init() }

    public func schedule() {
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .notDetermined:
            if #available(OSX 10.14, *) {
                manager.requestLocation()
            } else {
                manager.startUpdatingLocation()
            }
        default:
            schedule(atLocation: nil)
        }
    }

    private var task: Task?

    #warning("FIXME: This is what I have after 3 months of consideration, but can do better")
    private func schedule(atLocation location: CLLocation?) {
        guard preferences.scheduled else { return cancel() }
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        if let coordinate = location?.coordinate
            , CLLocationCoordinate2DIsValid(coordinate)
            , preferences.scheduleZenithType != .custom {
            let scheduledDate: Date
            let solar = Solar(for: now, coordinate: coordinate)!
            let dates = solar.sunriseSunsetTime
            if now < dates.sunrise {
                AppleInterfaceStyle.darkAqua.enable()
                scheduledDate = dates.sunrise
                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
                let pastSolar = Solar(for: yesterday, coordinate: coordinate)!
                preferences.scheduleStart = pastSolar.sunriseSunsetTime.sunset
                preferences.scheduleEnd = scheduledDate
            } else {
                let futureSolar = Solar(for: tomorrow, coordinate: coordinate)!
                let futureDates = futureSolar.sunriseSunsetTime
                if now < dates.sunset {
                    AppleInterfaceStyle.aqua.enable()
                    scheduledDate = dates.sunset
                    preferences.scheduleStart = scheduledDate
                    preferences.scheduleEnd = futureDates.sunrise
                } else { // after sunset
                    AppleInterfaceStyle.darkAqua.enable()
                    preferences.scheduleStart = dates.sunset
                    scheduledDate = futureDates.sunrise
                    preferences.scheduleEnd = scheduledDate
                }
            }
            return task = Schedule.at(scheduledDate).do(onElapse: schedule)
        }
        // Avoid recursion in a bad way, but ok
        guard preferences.scheduleZenithType == .custom else {
            return preferences.scheduleZenithType = .custom
        }
        #warning("FIXME: This is gonna be a catastrophe when a user moves across timezone")
        let current = Calendar.current.dateComponents([.hour, .minute], from: now)
        let start = Calendar.current.dateComponents(
            [.hour, .minute], from: preferences.scheduleStart
        )
        let end = Calendar.current.dateComponents(
            [.hour, .minute], from: preferences.scheduleEnd
        )
        let scheduledDate: Date
        if current.hour! <= end.hour! && current.minute! < end.minute! {
            AppleInterfaceStyle.darkAqua.enable()
            scheduledDate = Calendar.current.date(
                bySettingHour: end.hour!, minute: end.minute!, second: 0, of: now
            )!
        } else if current.hour! <= start.hour! && current.minute! < start.minute! {
            AppleInterfaceStyle.aqua.enable()
            scheduledDate = Calendar.current.date(
                bySettingHour: start.hour!, minute: start.minute!, second: 0, of: now
            )!
        } else {
            AppleInterfaceStyle.darkAqua.enable()
            scheduledDate = Calendar.current.date(
                bySettingHour: end.hour!, minute: end.minute!, second: 0, of: tomorrow
            )!
        }
        task = Schedule.at(scheduledDate).do(onElapse: schedule)
    }

    public func cancel() {
        task?.cancel()
    }

    // MARK: - Real World

    private lazy var manager: CLLocationManager = {
        var manager: CLLocationManager!
        DispatchQueue.main.sync {
            manager = CLLocationManager()
        }
        manager.delegate = self
        return manager
    }()

    public func locationManager(_ manager: CLLocationManager,
                                didChangeAuthorization status: CLAuthorizationStatus) {
        if status != .authorizedAlways {
            print("denied")
            schedule(atLocation: nil)
        }
    }

    public func locationManager(_ manager: CLLocationManager,
                                didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        manager.stopUpdatingLocation()
        schedule(atLocation: location)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSAlert(error: error).runModal()
        schedule(atLocation: nil)
    }
}

public enum Zenith: Int, CaseIterable {
    case official
    case civil
    case nautical
    case astronimical
    case custom
}

extension Solar {
    fileprivate var sunriseSunsetTime: (sunrise: Date, sunset: Date) {
        switch preferences.scheduleZenithType {
        case .custom:
            fatalError("No custom zenith type in solar")
        case .official:
            return (sunrise!, sunset!)
        case .civil:
            return (civilSunrise!, civilSunset!)
        case .nautical:
            return (nauticalSunrise!, nauticalSunset!)
        case .astronimical:
            return (astronomicalSunrise!, astronomicalSunset!)
        }
    }
}
