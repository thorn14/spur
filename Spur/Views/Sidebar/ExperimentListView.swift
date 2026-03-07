import SwiftUI

struct ExperimentListView: View {
    @EnvironmentObject var experimentViewModel: ExperimentViewModel

    var body: some View {
        List(
            experimentViewModel.experiments,
            id: \.id,
            selection: $experimentViewModel.selectedExperimentId
        ) { experiment in
            ExperimentRow(experiment: experiment)
                .tag(experiment.id)
        }
        .listStyle(.sidebar)
        .overlay {
            if experimentViewModel.experiments.isEmpty {
                EmptyExperimentsView()
            }
        }
    }
}

// MARK: - Row

private struct ExperimentRow: View {
    let experiment: Experiment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(experiment.name, systemImage: "flask")
                .lineLimit(1)
            Text("\(experiment.optionIds.count) option\(experiment.optionIds.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Empty state (macOS 13 compatible)

private struct EmptyExperimentsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "flask")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No experiments yet")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Click + below to create one.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}
