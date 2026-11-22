import Foundation
import SwiftData

@MainActor
enum VehicleService {
    /// 删除车辆以及它的所有行程、加油、费用和提醒
    static func delete(_ vehicle: Vehicle, context: ModelContext) {
        let vid = vehicle.id
        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { $0.vehicleID == vid }
        for trip in trips {
            TrackStore.delete(trip.id)
            TripExporter.deleteExports(id: trip.id, startDate: trip.startDate)
            context.delete(trip)
        }
        for entry in ((try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []) where entry.vehicleID == vid {
            context.delete(entry)
        }
        for expense in ((try? context.fetch(FetchDescriptor<Expense>())) ?? []) where expense.vehicleID == vid {
            context.delete(expense)
        }
        for reminder in ((try? context.fetch(FetchDescriptor<MaintenanceReminder>())) ?? []) where reminder.vehicleID == vid {
            context.delete(reminder)
        }
        context.delete(vehicle)
        try? context.save()
        if AppSettings.currentVehicleID == vid {
            AppSettings.currentVehicleID = nil
        }
        SeedData.ensureCurrentVehicle(context: context)
        ReminderEngine.rescheduleAll(context: context)
    }

    /// 第一辆车：把之前没有指定车辆的行程归到这辆车
    static func adoptUnassignedTrips(to vehicle: Vehicle, context: ModelContext) {
        let trips = ((try? context.fetch(FetchDescriptor<Trip>())) ?? []).filter { $0.vehicleID == nil }
        for trip in trips {
            trip.vehicleID = vehicle.id
        }
        try? context.save()
    }

    static func setCurrent(_ vehicle: Vehicle) {
        AppSettings.currentVehicleID = vehicle.id
    }
}
