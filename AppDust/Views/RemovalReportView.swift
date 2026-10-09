import SwiftUI

struct RemovalReportView: View {
    let results: [RemovalResult]
    @Binding var isPresented: Bool

    private var succeeded: [RemovalResult] { results.filter(\.success) }
    private var failed: [RemovalResult] { results.filter { !$0.success } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: failed.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(failed.isEmpty ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(failed.isEmpty ? "清理完成" : "清理完成，部分项目失败")
                        .font(.headline)
                    Text("成功 \(succeeded.count) 项，失败 \(failed.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)

            Divider()

            List {
                if !failed.isEmpty {
                    Section("失败") {
                        ForEach(failed) { row($0) }
                    }
                }
                if !succeeded.isEmpty {
                    Section("成功") {
                        ForEach(succeeded) { row($0) }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            Divider()

            HStack {
                Spacer()
                Button("关闭") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 620, height: 460)
    }

    private func row(_ result: RemovalResult) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle" : "xmark.circle")
                .foregroundStyle(result.success ? Color.green : Color.red)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                Text(result.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                if let message = result.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(result.success ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
