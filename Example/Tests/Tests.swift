import XCTest
import RealmSwift
import com_awareframework_ios_sensor_ambientnoise
import com_awareframework_ios_sensor_core

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
    
    var token1:NotificationToken? = nil
    
    func testSensorModule(){
        
        #if targetEnvironment(simulator)
        
        print("This test requires a real device.")
        
        #else

        let sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config().apply{ config in
            config.debug = true
            config.dbType = .REALM
            config.dbPath = "sensor_module"
        })
        let expect = expectation(description: "sensor module")
        if let realmEngine = sensor.dbEngine as? RealmEngine {
            // remove old data
            realmEngine.removeAll(AmbientNoiseData.self)
            // get a RealmEngine Instance
            if let realm = realmEngine.getRealmInstance() {
                // set Realm DB observer
                token1 = realm.observe { (notification, realm) in
                    switch notification {
                    case .didChange:
                        // check database size
                        let results = realm.objects(AmbientNoiseData.self)
                        print(results.count)
                        XCTAssertGreaterThanOrEqual(results.count, 1)
                        realm.invalidate()
                        expect.fulfill()
                        self.token1 = nil
                        break;
                    case .refreshRequired:
                        break;
                    }
                }
            }
        }
        
        var storageExpect:XCTestExpectation? = expectation(description: "sensor storage notification")
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareAmbientNoise,
                                                              object: sensor,
                                                              queue: .main) { (notification) in
                                                                if let exp = storageExpect {
                                                                    exp.fulfill()
                                                                    storageExpect = nil
                                                                    NotificationCenter.default.removeObserver(token!)
                                                                }

        }
        
        sensor.start() // start sensor
        
        wait(for: [expect,storageExpect!], timeout: 10)
        sensor.stop()
        #endif
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
        let labelObserver = NotificationCenter.default.addObserver(forName: .actionAwareAmbientNoiseSetLabel, object: sensor, queue: .main) { (notification) in
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
    
    func testSyncModule(){
        #if targetEnvironment(simulator)
        
        print("This test requires a real AmbientNoise.")
        
        #else
        // success //
        let sensor = AmbientNoiseSensor.init(AmbientNoiseSensor.Config().apply{ config in
            config.debug = true
            config.dbType = .REALM
            config.dbHost = "node.awareframework.com:1001"
            config.dbPath = "sync_db"
        })
        if let engine = sensor.dbEngine as? RealmEngine {
            engine.removeAll(AmbientNoiseData.self)
            for _ in 0..<100 {
                engine.save(AmbientNoiseData())
            }
        }
        let successExpectation = XCTestExpectation(description: "success sync")
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareAmbientNoiseSyncCompletion,
                                                              object: sensor, queue: .main) { (notification) in
                                                                if let userInfo = notification.userInfo{
                                                                    if let status = userInfo["status"] as? Bool {
                                                                        if status == true {
                                                                            successExpectation.fulfill()
                                                                        }
                                                                    }
                                                                }
        }
        sensor.sync(force: true)
        wait(for: [successExpectation], timeout: 20)
        NotificationCenter.default.removeObserver(observer)
        
        ////////////////////////////////////
        
        // failure //
        let sensor2 = AmbientNoiseSensor.init(AmbientNoiseSensor.Config().apply{ config in
            config.debug = true
            config.dbType = .REALM
            config.dbHost = "node.awareframework.com.com" // wrong url
            config.dbPath = "sync_db"
        })
        let failureExpectation = XCTestExpectation(description: "failure sync")
        let failureObserver = NotificationCenter.default.addObserver(forName: Notification.Name.actionAwareAmbientNoiseSyncCompletion,
                                                                     object: sensor2, queue: .main) { (notification) in
                                                                        if let userInfo = notification.userInfo{
                                                                            if let status = userInfo["status"] as? Bool {
                                                                                if status == false {
                                                                                    failureExpectation.fulfill()
                                                                                }
                                                                            }
                                                                        }
        }
        if let engine = sensor2.dbEngine as? RealmEngine {
            engine.removeAll(AmbientNoiseData.self)
            for _ in 0..<100 {
                engine.save(AmbientNoiseData())
            }
        }
        sensor2.sync(force: true)
        wait(for: [failureExpectation], timeout: 20)
        NotificationCenter.default.removeObserver(failureObserver)
        
        #endif
    }

}
