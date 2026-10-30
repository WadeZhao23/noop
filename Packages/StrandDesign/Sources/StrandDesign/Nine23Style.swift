import SwiftUI

/// Apple reference edition tokens. Existing NOOP themes and analytics remain independent.
public enum Nine23Style {
    public static let canvas = Color(light: "#EDF0F2", dark: "#11181D")
    public static let surface = Color(light: "#FFFFFF", dark: "#20292F")
    public static let raised = Color(light: "#E5EAEF", dark: "#2A343C")
    public static let line = Color(light: "#D3DBE1", dark: "#36424A")
    public static let text = Color(light: "#14202A", dark: "#F5F7F9")
    public static let secondary = Color(light: "#536471", dark: "#A7B4BD")
    public static let sleep = Color(light: "#58738F", dark: "#AFBDD0")
    public static let recovery = Color(light: "#398619", dark: "#83E348")
    public static let activity = Color(light: "#176EB7", dark: "#54A6F1")
    public static let yellow = Color(light: "#9B6A00", dark: "#F1CB45")
    public static let red = Color(light: "#C23D47", dark: "#F46973")
    public static let rem = Color(light: "#8463B6", dark: "#B4A0E3")
    public static let deep = Color(light: "#394B9A", dark: "#6275CA")
    public static let page: CGFloat = 20
    public static let gap: CGFloat = 16
    public static let small: CGFloat = 8
    public static let section: CGFloat = 28
    public static let radius: CGFloat = 12
    public static let chartHeight: CGFloat = 190
    public static let minimumTap: CGFloat = 44
    public static let title = Font.system(.title2, weight: .bold)
    public static let heading = Font.system(.headline, weight: .semibold)
    public static let body = Font.system(.subheadline)
    public static let caption = Font.system(.caption)
    public static let label = Font.system(.caption2, weight: .bold)
    public static let score = Font.system(.largeTitle, weight: .bold).monospacedDigit()
    public static let value = Font.system(.title2, weight: .bold).monospacedDigit()
    public static func accent(_ key: String, value: Double? = nil) -> Color {
        if key == "recovery", let value { return value >= 67 ? recovery : value >= 34 ? yellow : red }
        if ["sleep", "rest"].contains(key) { return sleep }
        if key == "recovery" { return recovery }
        return activity
    }
}
