import SwiftUI

/// The device and line settings of a serial connection, as in PuTTY's Serial page.
struct SerialSection: View {
    @Binding var device: String
    @Binding var options: SerialOptions

    @State private var devices: [String] = []

    private var trimmedDevice: String { device.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Section {
            LabeledContent("Device") {
                HStack {
                    TextField("Device", text: $device, prompt: Text(verbatim: "/dev/cu.usbserial-0001"))
                        .labelsHidden()
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Menu("Devices", systemImage: "cable.connector") {
                        if devices.isEmpty {
                            Text("No serial devices are connected")
                        }
                        ForEach(devices, id: \.self) { path in
                            Button(path) { device = path }
                        }
                        Divider()
                        Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Connected serial devices")
                }
            }
            if !trimmedDevice.isEmpty, !devices.contains(trimmedDevice) {
                Text("This device isn't connected right now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Speed") {
                HStack {
                    TextField("Speed", value: $options.baudRate, format: .number.grouping(.never))
                        .labelsHidden()
                    Menu("Common Speeds", systemImage: "chevron.up.chevron.down") {
                        ForEach(SerialOptions.commonBaudRates, id: \.self) { rate in
                            Button(String(rate)) { options.baudRate = rate }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Common speeds")
                }
            }
            if !SerialOptions.baudRateRange.contains(options.baudRate) {
                Text("Speed must be between \(String(SerialOptions.baudRateRange.lowerBound)) and \(String(SerialOptions.baudRateRange.upperBound)).")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker("Data Bits", selection: $options.dataBits) {
                ForEach(SerialOptions.dataBitChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            Picker("Parity", selection: $options.parity) {
                ForEach(SerialParity.allCases) { Text($0.title).tag($0) }
            }
            Picker("Stop Bits", selection: $options.stopBits) {
                ForEach(SerialOptions.stopBitChoices, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            Picker("Flow Control", selection: $options.flowControl) {
                ForEach(SerialFlowControl.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text("Serial Port")
        } footer: {
            Text("Opens in your terminal app. Press Ctrl-A, then Q to close the connection.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            refresh()
            // A new connection starts on the only plugged-in device, if there is one.
            if trimmedDevice.isEmpty, devices.count == 1 { device = devices[0] }
        }
    }

    private func refresh() {
        devices = SerialDevices.available()
    }
}
