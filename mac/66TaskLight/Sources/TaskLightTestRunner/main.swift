import Testing
import TaskLightTestSuite

@main
struct TaskLightTestRunner {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
