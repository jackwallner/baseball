import SwiftUI

struct AboutView: View {
    let lastUpdated: Date?

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                aboutCard
                refreshCard
                versionCard
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(SavantPalette.canvas.ignoresSafeArea())
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "STATSCOUT")
            HStack(spacing: 12) {
                Image(systemName: "baseball.fill")
                    .font(.title2)
                    .foregroundStyle(SavantPalette.savantRed)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baseball Savant-style Percentiles")
                        .font(SavantType.cardTitle)
                        .foregroundStyle(SavantPalette.ink)
                    Text("Mobile-first percentile rankings and leaderboards for fans and media.")
                        .font(SavantType.small)
                        .foregroundStyle(SavantPalette.inkSecondary)
                }
                Spacer()
            }
            .padding(SavantGeo.padCard)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var refreshCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "DATA")
            row(
                icon: "moon.stars.fill",
                title: "Nightly Refresh",
                subtitle: "Refreshed each night via GitHub Actions using Baseball Savant / Statcast feeds."
            )
            Rectangle().fill(SavantPalette.divider).frame(height: SavantGeo.hairline)
            row(
                icon: "clock.arrow.circlepath",
                title: "Last Updated",
                subtitle: lastUpdated.map { $0.formatted(date: .long, time: .shortened) } ?? "—"
            )
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private var versionCard: some View {
        VStack(spacing: 0) {
            SavantSectionBar(title: "VERSION")
            HStack {
                Text("App Version")
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Spacer()
                Text(version)
                    .font(SavantType.statSmall)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            .padding(SavantGeo.padCard)
        }
        .background(SavantPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: SavantGeo.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: SavantGeo.radiusCard)
                .stroke(SavantPalette.hairline, lineWidth: 0.5)
        )
    }

    private func row(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(SavantPalette.savantRed)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SavantType.bodyBold)
                    .foregroundStyle(SavantPalette.ink)
                Text(subtitle)
                    .font(SavantType.small)
                    .foregroundStyle(SavantPalette.inkSecondary)
            }
            Spacer()
        }
        .padding(SavantGeo.padCard)
    }
}

#Preview {
    NavigationStack {
        AboutView(lastUpdated: Date())
    }
}
