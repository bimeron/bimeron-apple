import BimeronStatistics
import SwiftUI

struct StatisticsView: View {
    let snapshot: ConnectionStatistics?
    let translate: (String) -> String
    let locale: Locale

    var body: some View {
        let presentation = StatisticsPresentation(snapshot: snapshot)
        VStack(alignment: .leading, spacing: 6) {
            Text(translate("Connection statistics"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            metric("Download total", value: presentation.totals.map { StatisticsPresentation.bytes($0.bytesDown, locale: locale) })
            metric("Upload total", value: presentation.totals.map { StatisticsPresentation.bytes($0.bytesUp, locale: locale) })
            metric("Download rate", value: rate(presentation.rate?.bytesDownPerSecond))
            metric("Upload rate", value: rate(presentation.rate?.bytesUpPerSecond))
            DisclosureGroup(translate("Retained observations")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(translate("Bounded history; gaps are unavailable observations."))
                        .foregroundStyle(.secondary)
                    if presentation.history.isEmpty {
                        Text(translate("No retained observations"))
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(presentation.history, id: \.elapsed) { sample in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(translate("Monotonic elapsed") + ": " + StatisticsPresentation.elapsed(sample.elapsed, locale: locale) + " " + translate("s"))
                                        metric("Download total", value: sample.counters.map { StatisticsPresentation.bytes($0.bytesDown, locale: locale) })
                                        metric("Upload total", value: sample.counters.map { StatisticsPresentation.bytes($0.bytesUp, locale: locale) })
                                        metric("Download rate", value: rate(sample.rate?.bytesDownPerSecond))
                                        metric("Upload rate", value: rate(sample.rate?.bytesUpPerSecond))
                                    }
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                }
            }
            .font(.caption)
        }
        .monospacedDigit()
        .frame(maxWidth: 360, alignment: .leading)
    }

    private func metric(_ key: String, value: String?) -> some View {
        LabeledContent(translate(key), value: value ?? translate("Unavailable"))
    }

    private func rate(_ value: Double?) -> String? {
        value.map { StatisticsPresentation.number($0, locale: locale) + " " + translate("B/s") }
    }
}
