import XCTest
import com_awareframework_ios_sensor_ambientnoise

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        XCTAssert(true, "Pass")
    }
    
    func testConfig(){
        // Sampling interval in minute. (default = 5)
        let interval:Int            = 10;
        // samples: Int : Data samples to collect per minute. (default = 30)
        let samples:Int             = 60;
        // silenceThreshold: Double: A threshold of RMS for determining silence or not. (default = 50)
        let silenceThreshold:Double = 80.0;
        
        // default
        var sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config.init())
        XCTAssertEqual(5, sensor.CONFIG.interval)
        XCTAssertEqual(30, sensor.CONFIG.samples)
        XCTAssertEqual(50.0, sensor.CONFIG.silenceThreshold)
        
        // inti with dictionary
        sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config.init(["interval": interval, "samples":samples, "silenceThreshold": silenceThreshold]))
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        XCTAssertEqual(samples, sensor.CONFIG.samples)
        XCTAssertEqual(silenceThreshold, sensor.CONFIG.silenceThreshold)
        
        // set
        sensor = AmbientNoiseSensor()
        sensor.CONFIG.set(config: ["interval": interval, "samples":samples, "silenceThreshold": silenceThreshold])
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        XCTAssertEqual(samples,  sensor.CONFIG.samples)
        XCTAssertEqual(silenceThreshold, sensor.CONFIG.silenceThreshold)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
