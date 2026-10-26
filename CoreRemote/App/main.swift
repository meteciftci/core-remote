import Foundation

// A serial connection's terminal window runs this executable as its console; see `SerialConsole`.
if CommandLine.arguments.dropFirst().first == SerialConsole.flag {
    exit(SerialConsole.run(Array(CommandLine.arguments.dropFirst(2))))
}
CoreRemoteApp.main()
