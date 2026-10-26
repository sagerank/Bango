import Foundation

public enum RecordingError: Error, Equatable {
    case badHeader
    case badRow(Int)
}

/// CSV format for recorded sensor sessions, so detector changes can be tested without a MacBook.
/// Columns: t,ax,ay,az,gx,gy,gz,idle. Gyro columns are empty when no gyroscope was present.
public enum RecordingCSV {
    public static let header = "t,ax,ay,az,gx,gy,gz,idle"

    public static func encode(_ samples: [SensorSample]) -> String {
        var lines = [header]
        lines.reserveCapacity(samples.count + 1)
        for s in samples {
            var fields: [String] = [
                "\(s.time)", "\(s.accel.x)", "\(s.accel.y)", "\(s.accel.z)",
            ]
            if let g = s.gyro {
                fields += ["\(g.x)", "\(g.y)", "\(g.z)"]
            } else {
                fields += ["", "", ""]
            }
            fields.append("\(s.inputIdle)")
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func decode(_ text: String) throws -> [SensorSample] {
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == header else {
            throw RecordingError.badHeader
        }
        var samples: [SensorSample] = []
        samples.reserveCapacity(lines.count)
        for (offset, line) in lines.dropFirst().enumerated() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8,
                  let t = Double(fields[0]),
                  let ax = Double(fields[1]),
                  let ay = Double(fields[2]),
                  let az = Double(fields[3]),
                  let idle = Double(fields[7])
            else {
                throw RecordingError.badRow(offset + 2)
            }
            var gyro: Vec3?
            if let gx = Double(fields[4]), let gy = Double(fields[5]), let gz = Double(fields[6]) {
                gyro = Vec3(gx, gy, gz)
            }
            samples.append(SensorSample(time: t, accel: Vec3(ax, ay, az), gyro: gyro, inputIdle: idle))
        }
        return samples
    }
}
