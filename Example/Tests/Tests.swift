import XCTest
import RealmSwift
import com_awareframework_ios_sensor_ambientnoise

class Tests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
        Realm.Configuration.defaultConfiguration.inMemoryIdentifier = self.name
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testObserver(){
        
        #if targetEnvironment(simulator)
        print("This test requires a real device.")

        #else
        
        class Observer:AmbientNoiseObserver{
            
            weak var ambientNoiseExpectation: XCTestExpectation?
            func onAmbientNoiseChanged(data: AmbientNoiseData) {
                print(#function)
                self.ambientNoiseExpectation?.fulfill()
            }
            
        }
        
        let ambientNoiseObserverExpect = expectation(description: "AmbientNoise observer")
        let observer = Observer()
        observer.ambientNoiseExpectation = ambientNoiseObserverExpect
        let sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config().apply{ config in
            config.sensorObserver = observer
            config.dbType = .REALM
        })
        
//        let ambientNoiseStorageExpect:XCTestExpectation? = expectation(description: "AmbientNoise storage")
//        let obs = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareAmbientNoise,
//             object: nil,
//             queue: .main) { (notification) in
//            if let engine = sensor.dbEngine {
//                if let results = engine.fetch(AmbientNoiseData.TABLE_NAME, AmbientNoiseData.self, nil) as? Results<Object>{
//                    print(results)
//                    if let expect = ambientNoiseStorageExpect {
//                        expect.fulfill()
//                        XCTAssertEqual(results.count, 1)
//                    }
//
//                }else{
//                    XCTFail()
//                }
//            }
//        }
        
        sensor.start()
        
        wait(for: [ambientNoiseObserverExpect], timeout: 10)
        sensor.stop()
//        NotificationCenter.default.removeObserver(obs)
        
        #endif
    }
    
    func testControllers() {
        let sensor = AmbientNoiseSensor()
        
        /// test set label action ///
        let expectSetLabel = expectation(description: "set label")
        let newLabel = "hello"
        let labelObserver = NotificationCenter.default.addObserver(forName: .actionAwareAmbientNoiseSetLabel, object: nil, queue: .main) { (notification) in
            let dict = notification.userInfo;
            if let d = dict as? Dictionary<String,String>{
                XCTAssertEqual(d[AmbientNoiseSensor.EXTRA_LABEL], newLabel)
            }else{
                XCTFail()
            }
            expectSetLabel.fulfill()
        }
        sensor.set(label:newLabel)
        wait(for: [expectSetLabel], timeout: 5)
        NotificationCenter.default.removeObserver(labelObserver)
        
        /// test sync action ////
        let expectSync = expectation(description: "sync")
        let syncObserver = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareAmbientNoiseSync , object: nil, queue: .main) { (notification) in
            expectSync.fulfill()
            print("sync")
        }
        sensor.sync()
        wait(for: [expectSync], timeout: 5)
        NotificationCenter.default.removeObserver(syncObserver)
        
        
        #if targetEnvironment(simulator)
        print("This test requires a real device.")

        #else
        
        //// test start action ////
        let expectStart = expectation(description: "start")
        let observer = NotificationCenter.default.addObserver(forName: .actionAwareAmbientNoiseStart,
                                                              object: nil,
                                                              queue: .main) { (notification) in
                                                                expectStart.fulfill()
                                                                print("start")
        }
        sensor.start()
        wait(for: [expectStart], timeout: 5)
        NotificationCenter.default.removeObserver(observer)
        
        
        /// test stop action ////
        let expectStop = expectation(description: "stop")
        let stopObserver = NotificationCenter.default.addObserver(forName: .actionAwareAmbientNoiseStop, object: nil, queue: .main) { (notification) in
            expectStop.fulfill()
            print("stop")
        }
        sensor.stop()
        wait(for: [expectStop], timeout: 5)
        NotificationCenter.default.removeObserver(stopObserver)
        
        #endif
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
        
        sensor.CONFIG.interval = -1
        XCTAssertEqual(interval, sensor.CONFIG.interval)
        
        sensor.CONFIG.samples = 0
        XCTAssertEqual(samples,  sensor.CONFIG.samples)
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure() {
            // Put the code you want to measure the time of here.
        }
    }
    
}
