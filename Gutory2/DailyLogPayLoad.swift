//  DailyLogPayload.swift
//  Gutory2
//
//  Shared model for rows in the `daily_logs` table.

import Foundation

struct DailyLogPayload: Codable {
    let userId: String
    let logDate: String

    // Free-text meals / notes
    let mealsText: String?

    // Gut symptoms
    let bloating: Int?
    let abdominalPain: Int?
    let gas: Int?
    let stoolQuality: Int?
    let nauseaReflux: Int?

    // Wellbeing metrics
    let energyLevel: Int?
    let brainFog: Int?
    let mood: Int?
    let skinQuality: Int?

    // Sleep / stress / lifestyle
    let sleepQuality: Int?
    let stressLevel: Int?
    let waterIntake: Int?
    let exerciseLevel: Int?

    enum CodingKeys: String, CodingKey {
        case userId        = "user_id"
        case logDate       = "log_date"

        case mealsText     = "meals_text"

        case bloating
        case abdominalPain = "abdominal_pain"
        case gas
        case stoolQuality  = "stool_quality"
        case nauseaReflux  = "nausea_reflux"

        case energyLevel   = "energy_level"
        case brainFog      = "brain_fog"
        case mood
        case skinQuality   = "skin_quality"

        case sleepQuality  = "sleep_quality"
        case stressLevel   = "stress_level"
        case waterIntake   = "water_intake"
        case exerciseLevel = "exercise_level"
    }
}
